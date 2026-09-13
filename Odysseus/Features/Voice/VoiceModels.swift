import Foundation

enum VoiceTask: String, Codable { case stt, tts }

/// Model language bucket. `universal` = the multilingual checkpoints (Whisper
/// large/turbo, Parakeet v3); the rest are language-tuned checkpoints, one
/// bucket per language the catalog ships a tuned model for. Text labels only —
/// no flags (flags misrepresent languages spoken across regions).
///
/// Raw values are stable storage keys (the Settings filter persists them),
/// so new cases append and nothing is renamed.
enum VoiceLang: String, Codable, CaseIterable {
    case universal
    case english, portuguese, chinese, japanese, french
    // 1.11: one tuned checkpoint per language, hosted under JoaoZaokk on HF.
    case spanish, german, italian, korean, russian, arabic, hindi, turkish, thai
    case swedish, finnish, vietnamese, hebrew, hungarian, croatian

    // Old installs stored "bilingual" for the multilingual models.
    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? "universal"
        self = VoiceLang(rawValue: raw == "bilingual" ? "universal" : raw) ?? .universal
    }

    /// Whisper language code the tuned models pin (nil = follow the setting).
    var whisperCode: String? {
        switch self {
        case .universal:  nil
        case .english:    "en"
        case .portuguese: "pt"
        case .chinese:    "zh"
        case .japanese:   "ja"
        case .french:     "fr"
        case .spanish:    "es"
        case .german:     "de"
        case .italian:    "it"
        case .korean:     "ko"
        case .russian:    "ru"
        case .arabic:     "ar"
        case .hindi:      "hi"
        case .turkish:    "tr"
        case .thai:       "th"
        case .swedish:    "sv"
        case .finnish:    "fi"
        case .vietnamese: "vi"
        case .hebrew:     "he"
        case .hungarian:  "hu"
        case .croatian:   "hr"
        }
    }

    /// The six original buckets keep their catalogue keys (translated in every
    /// language); the rest are named by Foundation in the app's language, which
    /// spares 43 catalogues × 17 keys for something ICU already knows.
    var label: String {
        switch self {
        case .universal:  return L("Universal")
        case .english:    return L("Inglês")
        case .portuguese: return L("Português")
        case .chinese:    return L("Chinês")
        case .japanese:   return L("Japonês")
        case .french:     return L("Francês")
        default:
            guard let code = whisperCode,
                  let name = Self.displayLocale.localizedString(forLanguageCode: code), !name.isEmpty
            else { return rawValue }
            return name.prefix(1).uppercased() + name.dropFirst()
        }
    }

    /// The locale the app is showing (Ajustes › Idioma), read the same way
    /// `LocalizationManager` stores it so this works off the main actor.
    private static var displayLocale: Locale {
        if let raw = UserDefaults.standard.string(forKey: "app.language"), raw != "auto" {
            return Locale(identifier: raw)
        }
        return Locale.current
    }
}

/// A downloadable on-device speech model (single-file). STT = whisper.cpp ggml
/// (Whisper or Parakeet, see `engine`). Sizes are approximate.
struct VoiceModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let task: VoiceTask
    let lang: VoiceLang
    let bytes: Int64
    let url: URL

    /// Which C engine loads the file. Encoded in the id prefix so custom
    /// (`u-`) and legacy (`w-`) ids keep working unchanged: only `p-` is
    /// Parakeet.
    var engine: STTModelEngine { id.hasPrefix("p-") ? .parakeet : .whisper }

    /// On-disk name. `localURL` prefixes it with the model id, so this only has
    /// to be file-system safe — a URL that ends in a slash or carries a query
    /// would otherwise yield an empty or path-bearing name.
    var filename: String {
        let last = url.lastPathComponent.replacingOccurrences(of: "/", with: "")
        return last.isEmpty ? "model.bin" : last
    }

    /// Added by the user from a URL (see `CustomModels`), not from the shipped
    /// catalog. Same "u-" prefix convention the download manager uses for its
    /// "ml:" Core ML tasks.
    var isCustom: Bool { id.hasPrefix("u-") }

    /// Size bucket the user asked to group by.
    enum Bucket: String, CaseIterable {
        case mb500 = "Até 500 MB", gb1 = "Até 1 GB", gb2 = "Até 2 GB", gb3 = "Até 3 GB"
        /// Localized display label (rawValue stays as the stable identity/key).
        var label: String { L(rawValue) }
    }
    var bucket: Bucket {
        let mb = Double(bytes) / 1_000_000
        if mb <= 500 { return .mb500 }
        if mb <= 1000 { return .gb1 }
        if mb <= 2000 { return .gb2 }
        return .gb3
    }

    var humanSize: String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

/// A Whisper model the user added by pasting a URL. Stored locally so the model
/// list survives relaunches; the file itself lives with the catalog downloads.
struct CustomVoiceModel: Codable, Sendable, Hashable {
    var id: String
    var name: String
    var urlString: String
    var bytes: Int64

    var model: VoiceModel? {
        guard let url = URL(string: urlString) else { return nil }
        // Always `.universal`: we can't know what a user-supplied checkpoint was
        // tuned for, and universal makes the transcriber follow the app language
        // instead of pinning a wrong one.
        return VoiceModel(id: id, name: name, task: .stt, lang: .universal, bytes: bytes, url: url)
    }
}

/// The user's own models. Read from every thread (the download delegate is
/// nonisolated), so the decoded list is cached behind a lock instead of
/// re-parsing UserDefaults on each SwiftUI body pass.
enum CustomModels {
    private static let key = "voice.stt.customModels"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [CustomVoiceModel]?

    static var list: [CustomVoiceModel] {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache }
        let data = UserDefaults.standard.data(forKey: key) ?? Data()
        let decoded = (try? JSONDecoder().decode([CustomVoiceModel].self, from: data)) ?? []
        cache = decoded
        return decoded
    }

    static func add(_ m: CustomVoiceModel) { write(list.filter { $0.id != m.id } + [m]) }
    static func remove(id: String) { write(list.filter { $0.id != id }) }

    private static func write(_ items: [CustomVoiceModel]) {
        lock.lock()
        cache = items
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: key)
        lock.unlock()
    }
}

enum VoiceCatalog {
    private static func whisper(_ file: String) -> URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(file)")!
    }

    /// Everything the app knows how to install: the shipped catalog plus the
    /// user's own URLs. Every lookup by id goes through here, so a custom model
    /// behaves exactly like a catalog one (select, delete, transcribe).
    static var all: [VoiceModel] { builtIn + CustomModels.list.compactMap(\.model) }

    private static let builtIn: [VoiceModel] = [
        // ── STT · Whisper (whisper.cpp GGUF) ──
        .init(id: "w-tiny",            name: "Whisper Tiny",            task: .stt, lang: .universal, bytes:  75_000_000, url: whisper("ggml-tiny.bin")),
        .init(id: "w-tiny-en",         name: "Whisper Tiny (EN)",       task: .stt, lang: .english,   bytes:  75_000_000, url: whisper("ggml-tiny.en.bin")),
        .init(id: "w-small-q5",        name: "Whisper Small q5",        task: .stt, lang: .universal, bytes: 181_000_000, url: whisper("ggml-small-q5_1.bin")),
        .init(id: "w-base",            name: "Whisper Base",            task: .stt, lang: .universal, bytes: 142_000_000, url: whisper("ggml-base.bin")),
        .init(id: "w-base-en",         name: "Whisper Base (EN)",       task: .stt, lang: .english,   bytes: 142_000_000, url: whisper("ggml-base.en.bin")),
        .init(id: "w-small",           name: "Whisper Small",           task: .stt, lang: .universal, bytes: 466_000_000, url: whisper("ggml-small.bin")),

        .init(id: "w-small-en",        name: "Whisper Small (EN)",      task: .stt, lang: .english,   bytes: 466_000_000, url: whisper("ggml-small.en.bin")),
        .init(id: "w-medium-q5",       name: "Whisper Medium q5",       task: .stt, lang: .universal, bytes: 539_000_000, url: whisper("ggml-medium-q5_0.bin")),
        .init(id: "w-medium-en-q5",    name: "Whisper Medium q5 (EN)",  task: .stt, lang: .english,   bytes: 539_000_000, url: whisper("ggml-medium.en-q5_0.bin")),
        .init(id: "w-turbo-q5",        name: "Whisper Large-v3 Turbo q5",task: .stt, lang: .universal, bytes: 574_000_000, url: whisper("ggml-large-v3-turbo-q5_0.bin")),
        .init(id: "w-largev2-q5",      name: "Whisper Large-v2 q5",     task: .stt, lang: .universal, bytes: 1_080_000_000, url: whisper("ggml-large-v2-q5_0.bin")),

        .init(id: "w-largev3-q5",      name: "Whisper Large-v3 q5",     task: .stt, lang: .universal, bytes: 1_080_000_000, url: whisper("ggml-large-v3-q5_0.bin")),
        .init(id: "w-medium",          name: "Whisper Medium",          task: .stt, lang: .universal, bytes: 1_530_000_000, url: whisper("ggml-medium.bin")),
        .init(id: "w-medium-en",       name: "Whisper Medium (EN)",     task: .stt, lang: .english,   bytes: 1_530_000_000, url: whisper("ggml-medium.en.bin")),
        .init(id: "w-turbo",           name: "Whisper Large-v3 Turbo",  task: .stt, lang: .universal, bytes: 1_620_000_000, url: whisper("ggml-large-v3-turbo.bin")),

        .init(id: "w-largev3",         name: "Whisper Large-v3",        task: .stt, lang: .universal, bytes: 3_100_000_000, url: whisper("ggml-large-v3.bin")),
        .init(id: "w-largev2",         name: "Whisper Large-v2",        task: .stt, lang: .universal, bytes: 3_090_000_000, url: whisper("ggml-large-v2.bin")),
        .init(id: "w-largev1",         name: "Whisper Large-v1",        task: .stt, lang: .universal, bytes: 3_090_000_000, url: whisper("ggml-large-v1.bin")),

        // ── NVIDIA Parakeet TDT (whisper.cpp's parakeet engine; ggml by JoaoZaokk) ──
        // v3 = 25 European languages (pt, en, es, de, fr, it, …), detects the
        // language itself; v2 = English only. No Core ML encoder.
        .init(id: "p-v3-q5",  name: "NVIDIA Parakeet TDT v3 q5",   task: .stt, lang: .universal, bytes:   433_901_039, url: mine("parakeet-tdt-0.6b-v3-ggml", "ggml-parakeet-tdt-0.6b-v3-q5_0.bin")),
        .init(id: "p-v3-q8",  name: "NVIDIA Parakeet TDT v3 q8",   task: .stt, lang: .universal, bytes:   668_757_119, url: mine("parakeet-tdt-0.6b-v3-ggml", "ggml-parakeet-tdt-0.6b-v3-q8_0.bin")),
        .init(id: "p-v2-q5",  name: "NVIDIA Parakeet TDT v2 EN q5", task: .stt, lang: .english,   bytes:   434_000_000, url: mine("parakeet-tdt-0.6b-v2-ggml", "ggml-parakeet-tdt-0.6b-v2-q5_0.bin")),
        .init(id: "p-v2-q8",  name: "NVIDIA Parakeet TDT v2 EN q8", task: .stt, lang: .english,   bytes:   669_000_000, url: mine("parakeet-tdt-0.6b-v2-ggml", "ggml-parakeet-tdt-0.6b-v2-q8_0.bin")),
        .init(id: "p-1b1-q5", name: "NVIDIA Parakeet TDT 1.1B EN q5", task: .stt, lang: .english,  bytes:   800_000_000, url: mine("parakeet-tdt-1.1b-ggml", "ggml-parakeet-tdt-1.1b-q5_0.bin")),
        .init(id: "p-1b1-q8", name: "NVIDIA Parakeet TDT 1.1B EN q8", task: .stt, lang: .english,  bytes: 1_200_000_000, url: mine("parakeet-tdt-1.1b-ggml", "ggml-parakeet-tdt-1.1b-q8_0.bin")),
        // Orukeet = Parakeet v3 further trained by oruk (cc-by-sa-4.0); beats v3
        // on Portuguese in FLEURS (3.7 vs 4.5 WER on its card).
        .init(id: "p-oru-q5", name: "Orukeet (Parakeet v3+) q5",  task: .stt, lang: .universal, bytes:   434_000_000, url: mine("orukeet-ggml", "ggml-orukeet-q5_0.bin")),
        .init(id: "p-oru-q8", name: "Orukeet (Parakeet v3+) q8",  task: .stt, lang: .universal, bytes:   669_000_000, url: mine("orukeet-ggml", "ggml-orukeet-q8_0.bin")),

        // ── Language-tuned Whisper checkpoints ──
        // Converted with whisper.cpp's own converter and re-hosted under
        // JoaoZaokk (each repo names its source and keeps its license) so the
        // links do not depend on a stranger's account. q5 for phones, q8 for
        // Macs. No f16 in the catalog: phones cannot hold it, and the memory gate
        // would refuse it anyway; the custom-URL field still accepts one.
        // Chinese — BELLE fine-tune of Large-v3 Turbo (apache-2.0).
        .init(id: "w-zh-turbo-q5",  name: "Belle Whisper Turbo ZH q5", task: .stt, lang: .chinese, bytes:   574_000_000, url: mine("Belle-whisper-large-v3-turbo-zh-ggml", "ggml-belle-whisper-large-v3-turbo-zh-q5_0.bin")),
        .init(id: "w-zh-turbo-q8",  name: "Belle Whisper Turbo ZH q8", task: .stt, lang: .chinese, bytes:   874_000_000, url: mine("Belle-whisper-large-v3-turbo-zh-ggml", "ggml-belle-whisper-large-v3-turbo-zh-q8_0.bin")),
        // Japanese — Kotoba v2.0 (distil Large-v3, apache-2.0).
        .init(id: "w-ja-kotoba-q5", name: "Kotoba Whisper JA q5",      task: .stt, lang: .japanese, bytes:   538_000_000, url: mine("kotoba-whisper-v2.0-ggml", "ggml-kotoba-whisper-v2.0-q5_0.bin")),
        .init(id: "w-ja-kotoba-q8", name: "Kotoba Whisper JA q8",      task: .stt, lang: .japanese, bytes:   810_000_000, url: mine("kotoba-whisper-v2.0-ggml", "ggml-kotoba-whisper-v2.0-q8_0.bin")),
        // English — official Distil-Whisper Large-v3.5 (MIT, ggml by distil-whisper).
        .init(id: "w-en-distil35",  name: "Distil Whisper EN v3.5",    task: .stt, lang: .english, bytes: 1_520_000_000,
              url: hf("distil-whisper/distil-large-v3.5-ggml", "ggml-model.bin")),
        // Portuguese (BR) — freds0 distil Large-v3 fine-tune (MIT).
        .init(id: "w-pt-distil-q5", name: "Distil Whisper PT-BR q5",   task: .stt, lang: .portuguese, bytes: 538_000_000, url: mine("distil-whisper-large-v3-ptbr-ggml", "ggml-distil-whisper-large-v3-ptbr-q5_0.bin")),
        .init(id: "w-pt-distil-q8", name: "Distil Whisper PT-BR q8",   task: .stt, lang: .portuguese, bytes: 810_000_000, url: mine("distil-whisper-large-v3-ptbr-ggml", "ggml-distil-whisper-large-v3-ptbr-q8_0.bin")),
        // French — bofenghuang distil Large-v3 (16 decoder layers, MIT).
        .init(id: "w-fr-distil-q5", name: "Distil Whisper FR q5",      task: .stt, lang: .french, bytes:   791_000_000, url: mine("whisper-large-v3-french-distil-dec16-ggml", "ggml-whisper-large-v3-french-distil-dec16-q5_0.bin")),
        .init(id: "w-fr-distil-q8", name: "Distil Whisper FR q8",      task: .stt, lang: .french, bytes: 1_200_000_000, url: mine("whisper-large-v3-french-distil-dec16-ggml", "ggml-whisper-large-v3-french-distil-dec16-q8_0.bin")),
        // Spanish (Latin America) — marianbasti Large-v3 Turbo (MIT).
        .init(id: "w-es-turbo-q5",  name: "Whisper Turbo LatAm ES q5", task: .stt, lang: .spanish, bytes: 574_000_000, url: mine("whisper-large-v3-turbo-latam-ggml", "ggml-whisper-large-v3-turbo-latam-q5_0.bin")),
        .init(id: "w-es-turbo-q8",  name: "Whisper Turbo LatAm ES q8", task: .stt, lang: .spanish, bytes: 874_000_000, url: mine("whisper-large-v3-turbo-latam-ggml", "ggml-whisper-large-v3-turbo-latam-q8_0.bin")),
        // German — primeline Large-v3 Turbo (apache-2.0).
        .init(id: "w-de-turbo-q5",  name: "Whisper Turbo DE q5",       task: .stt, lang: .german, bytes: 574_000_000, url: mine("whisper-large-v3-turbo-german-ggml", "ggml-whisper-large-v3-turbo-german-q5_0.bin")),
        .init(id: "w-de-turbo-q8",  name: "Whisper Turbo DE q8",       task: .stt, lang: .german, bytes: 874_000_000, url: mine("whisper-large-v3-turbo-german-ggml", "ggml-whisper-large-v3-turbo-german-q8_0.bin")),
        // Italian — bofenghuang distil Large-v3 v0.2 (MIT).
        .init(id: "w-it-distil-q5", name: "Distil Whisper IT q5",      task: .stt, lang: .italian, bytes: 538_000_000, url: mine("whisper-large-v3-distil-it-v0.2-ggml", "ggml-whisper-large-v3-distil-it-v0.2-q5_0.bin")),
        .init(id: "w-it-distil-q8", name: "Distil Whisper IT q8",      task: .stt, lang: .italian, bytes: 810_000_000, url: mine("whisper-large-v3-distil-it-v0.2-ggml", "ggml-whisper-large-v3-distil-it-v0.2-q8_0.bin")),
        // Korean — royshilkrot Large-v3 Turbo (apache-2.0).
        .init(id: "w-ko-turbo-q5",  name: "Whisper Turbo KO q5",       task: .stt, lang: .korean, bytes: 574_000_000, url: mine("whisper-large-v3-turbo-korean-ggml", "ggml-whisper-large-v3-turbo-korean-q5_0.bin")),
        .init(id: "w-ko-turbo-q8",  name: "Whisper Turbo KO q8",       task: .stt, lang: .korean, bytes: 874_000_000, url: mine("whisper-large-v3-turbo-korean-ggml", "ggml-whisper-large-v3-turbo-korean-q8_0.bin")),
        // Russian — bond005 Podlodka Turbo (apache-2.0).
        .init(id: "w-ru-turbo-q5",  name: "Podlodka Whisper Turbo RU q5", task: .stt, lang: .russian, bytes: 574_000_000, url: mine("whisper-podlodka-turbo-ggml", "ggml-whisper-podlodka-turbo-q5_0.bin")),
        .init(id: "w-ru-turbo-q8",  name: "Podlodka Whisper Turbo RU q8", task: .stt, lang: .russian, bytes: 874_000_000, url: mine("whisper-podlodka-turbo-ggml", "ggml-whisper-podlodka-turbo-q8_0.bin")),
        // Arabic (dialects) — oddadmix Large-v3 Turbo v2 (apache-2.0).
        .init(id: "w-ar-turbo-q5",  name: "Whisper Turbo AR q5",       task: .stt, lang: .arabic, bytes: 574_000_000, url: mine("whisper-large-v3-turbo-arabic-dialectal-v2-ggml", "ggml-whisper-large-v3-turbo-arabic-dialectal-v2-q5_0.bin")),
        .init(id: "w-ar-turbo-q8",  name: "Whisper Turbo AR q8",       task: .stt, lang: .arabic, bytes: 874_000_000, url: mine("whisper-large-v3-turbo-arabic-dialectal-v2-ggml", "ggml-whisper-large-v3-turbo-arabic-dialectal-v2-q8_0.bin")),
        // Hindi — ARTPARK-IISc Vaani Large-v3 (apache-2.0; full-size model).
        .init(id: "w-hi-large-q5",  name: "Vaani Whisper Large-v3 HI q5", task: .stt, lang: .hindi, bytes: 1_080_000_000, url: mine("whisper-large-v3-vaani-hindi-ggml", "ggml-whisper-large-v3-vaani-hindi-q5_0.bin")),
        .init(id: "w-hi-large-q8",  name: "Vaani Whisper Large-v3 HI q8", task: .stt, lang: .hindi, bytes: 1_660_000_000, url: mine("whisper-large-v3-vaani-hindi-ggml", "ggml-whisper-large-v3-vaani-hindi-q8_0.bin")),
        // Turkish — turkmedstt Large-v3 general (apache-2.0; full-size model).
        .init(id: "w-tr-large-q5",  name: "Whisper Large-v3 TR q5",    task: .stt, lang: .turkish, bytes: 1_080_000_000, url: mine("whisper-large-v3-turkish-general-ggml", "ggml-whisper-large-v3-turkish-general-q5_0.bin")),
        .init(id: "w-tr-large-q8",  name: "Whisper Large-v3 TR q8",    task: .stt, lang: .turkish, bytes: 1_660_000_000, url: mine("whisper-large-v3-turkish-general-ggml", "ggml-whisper-large-v3-turkish-general-q8_0.bin")),
        // Thai — Typhoon Large-v3 Turbo (apache-2.0).
        .init(id: "w-th-turbo-q5",  name: "Typhoon Whisper Turbo TH q5", task: .stt, lang: .thai, bytes: 574_000_000, url: mine("typhoon-whisper-turbo-ggml", "ggml-typhoon-whisper-turbo-q5_0.bin")),
        .init(id: "w-th-turbo-q8",  name: "Typhoon Whisper Turbo TH q8", task: .stt, lang: .thai, bytes: 874_000_000, url: mine("typhoon-whisper-turbo-ggml", "ggml-typhoon-whisper-turbo-q8_0.bin")),
        // Swedish — KBLab kb-whisper-large (apache-2.0; full-size model).
        .init(id: "w-sv-large-q5",  name: "KB Whisper Large SV q5",    task: .stt, lang: .swedish, bytes: 1_080_000_000, url: mine("kb-whisper-large-ggml", "ggml-kb-whisper-large-q5_0.bin")),
        .init(id: "w-sv-large-q8",  name: "KB Whisper Large SV q8",    task: .stt, lang: .swedish, bytes: 1_660_000_000, url: mine("kb-whisper-large-ggml", "ggml-kb-whisper-large-q8_0.bin")),
        // Finnish — Finnish-NLP Large-v3 (apache-2.0; ggml f16 by the authors, quantized by JoaoZaokk).
        .init(id: "w-fi-large-q5",  name: "Whisper Large-v3 FI q5",    task: .stt, lang: .finnish, bytes: 1_080_000_000, url: mine("whisper-large-v3-finnish-ggml", "ggml-whisper-large-v3-finnish-q5_0.bin")),
        .init(id: "w-fi-large-q8",  name: "Whisper Large-v3 FI q8",    task: .stt, lang: .finnish, bytes: 1_660_000_000, url: mine("whisper-large-v3-finnish-ggml", "ggml-whisper-large-v3-finnish-q8_0.bin")),
        // Vietnamese — EraX WoW Turbo V1.1 (MIT).
        .init(id: "w-vi-turbo-q5",  name: "EraX Whisper Turbo VI q5",  task: .stt, lang: .vietnamese, bytes: 574_000_000, url: mine("EraX-WoW-Turbo-V1.1-ggml", "ggml-EraX-WoW-Turbo-V1.1-q5_0.bin")),
        .init(id: "w-vi-turbo-q8",  name: "EraX Whisper Turbo VI q8",  task: .stt, lang: .vietnamese, bytes: 874_000_000, url: mine("EraX-WoW-Turbo-V1.1-ggml", "ggml-EraX-WoW-Turbo-V1.1-q8_0.bin")),
        // Hebrew — ivrit.ai Large-v3 Turbo.
        .init(id: "w-he-turbo-q5",  name: "ivrit Whisper Turbo HE q5", task: .stt, lang: .hebrew, bytes: 574_000_000, url: mine("ivrit-whisper-large-v3-turbo-ggml", "ggml-ivrit-whisper-large-v3-turbo-q5_0.bin")),
        .init(id: "w-he-turbo-q8",  name: "ivrit Whisper Turbo HE q8", task: .stt, lang: .hebrew, bytes: 874_000_000, url: mine("ivrit-whisper-large-v3-turbo-ggml", "ggml-ivrit-whisper-large-v3-turbo-q8_0.bin")),
        // Hungarian — sarpba Large-v3 Turbo.
        .init(id: "w-hu-turbo-q5",  name: "Whisper Turbo HU q5",       task: .stt, lang: .hungarian, bytes: 574_000_000, url: mine("whisper-hu-large-v3-turbo-finetuned-ggml", "ggml-whisper-hu-large-v3-turbo-finetuned-q5_0.bin")),
        .init(id: "w-hu-turbo-q8",  name: "Whisper Turbo HU q8",       task: .stt, lang: .hungarian, bytes: 874_000_000, url: mine("whisper-hu-large-v3-turbo-finetuned-ggml", "ggml-whisper-hu-large-v3-turbo-finetuned-q8_0.bin")),
        // Croatian — GoranS Large-v3 Turbo (ParlaSpeech).
        .init(id: "w-hr-turbo-q5",  name: "Whisper Turbo HR q5",       task: .stt, lang: .croatian, bytes: 574_000_000, url: mine("whisper-large-v3-turbo-hr-parla-ggml", "ggml-whisper-large-v3-turbo-hr-parla-q5_0.bin")),
        .init(id: "w-hr-turbo-q8",  name: "Whisper Turbo HR q8",       task: .stt, lang: .croatian, bytes: 874_000_000, url: mine("whisper-large-v3-turbo-hr-parla-ggml", "ggml-whisper-large-v3-turbo-hr-parla-q8_0.bin")),
        // TTS agora é o PocketTTS (FluidAudio), que baixa os próprios modelos.
    ]

    private static func hf(_ repo: String, _ file: String) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file)")!
    }
    /// The owner's own conversions (ggml + quantizations), one repo per model.
    private static func mine(_ repo: String, _ file: String) -> URL {
        hf("JoaoZaokk/\(repo)", file)
    }

    /// nil = all models. `.universal` = only the multilingual ones. A specific
    /// language = that language's tuned models PLUS the universal ones (which
    /// support it too).
    static func filtered(task: VoiceTask, lang: VoiceLang?) -> [VoiceModel] {
        all.filter {
            guard $0.task == task else { return false }
            guard let lang else { return true }
            if lang == .universal { return $0.lang == .universal }
            return $0.lang == lang || $0.lang == .universal
        }
    }

    /// CoreML encoder (Neural Engine) zip for a Whisper model, by id. The encoder
    /// is shared across GGUF quantizations of the same size. nil = no CoreML.
    private static let coreMLByID: [String: String] = [
        "w-tiny": "ggml-tiny-encoder.mlmodelc.zip",
        "w-tiny-en": "ggml-tiny.en-encoder.mlmodelc.zip",
        "w-base": "ggml-base-encoder.mlmodelc.zip",
        "w-base-en": "ggml-base.en-encoder.mlmodelc.zip",
        "w-small": "ggml-small-encoder.mlmodelc.zip",
        "w-small-en": "ggml-small.en-encoder.mlmodelc.zip",
        "w-small-q5": "ggml-small-encoder.mlmodelc.zip",
        "w-medium": "ggml-medium-encoder.mlmodelc.zip",
        "w-medium-q5": "ggml-medium-encoder.mlmodelc.zip",
        "w-turbo": "ggml-large-v3-turbo-encoder.mlmodelc.zip",
        "w-turbo-q5": "ggml-large-v3-turbo-encoder.mlmodelc.zip",
        "w-largev3": "ggml-large-v3-encoder.mlmodelc.zip",
        "w-largev3-q5": "ggml-large-v3-encoder.mlmodelc.zip",
    ]

    static func coreMLZipURL(forID id: String) -> URL? {
        guard let f = coreMLByID[id] else { return nil }
        return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(f)")
    }

    /// Size of the Core ML encoder zip (≈ its resident weight, fp16 is
    /// incompressible), from the ggerganov/whisper.cpp file list. Shown before
    /// the download and counted against the memory budget: the encoder ADDS to
    /// the model's RAM, it does not replace the ggml encoder.
    static func coreMLZipBytes(forID id: String) -> Int64 {
        guard let f = coreMLByID[id] else { return 0 }
        switch f {
        case "ggml-tiny-encoder.mlmodelc.zip", "ggml-tiny.en-encoder.mlmodelc.zip":   return 16_000_000
        case "ggml-base-encoder.mlmodelc.zip", "ggml-base.en-encoder.mlmodelc.zip":   return 40_000_000
        case "ggml-small-encoder.mlmodelc.zip", "ggml-small.en-encoder.mlmodelc.zip": return 165_000_000
        case "ggml-medium-encoder.mlmodelc.zip":                                       return 600_000_000
        case "ggml-large-v3-turbo-encoder.mlmodelc.zip":                               return 1_173_000_000
        case "ggml-large-v3-encoder.mlmodelc.zip":                                     return 1_173_000_000
        default: return 0
        }
    }
}
