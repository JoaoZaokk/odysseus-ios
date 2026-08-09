import Foundation

enum VoiceTask: String, Codable { case stt, tts }

/// Model language bucket. `universal` = the multilingual Whisper checkpoints
/// (work for ~100 languages); the rest are language-tuned checkpoints. Text
/// labels only — no flags (flags misrepresent languages spoken across regions).
enum VoiceLang: String, Codable, CaseIterable {
    case universal, english, portuguese, chinese, japanese, french

    // Old installs stored "bilingual" for the multilingual models.
    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? "universal"
        self = VoiceLang(rawValue: raw == "bilingual" ? "universal" : raw) ?? .universal
    }

    var label: String {
        switch self {
        case .universal:  L("Universal")
        case .english:    L("Inglês")
        case .portuguese: L("Português")
        case .chinese:    L("Chinês")
        case .japanese:   L("Japonês")
        case .french:     L("Francês")
        }
    }
}

/// A downloadable on-device speech model (single-file). STT = whisper.cpp GGUF;
/// TTS = Kokoro ONNX. Sizes are approximate.
struct VoiceModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let task: VoiceTask
    let lang: VoiceLang
    let bytes: Int64
    let url: URL

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
    private static func kokoro(_ file: String) -> URL {
        URL(string: "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main/onnx/\(file)")!
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

        // ── Language-tuned checkpoints (community GGML, URLs verified live) ──
        // Chinese — BELLE fine-tunes of Large-v3 (Turbo).
        .init(id: "w-zh-turbo-q5",  name: "Belle Whisper Turbo ZH q5", task: .stt, lang: .chinese, bytes: 574_000_000,
              url: hf("uosx/Belle-whisper-large-v3-turbo-zh-ggml-quantized", "ggml-belle-large-v3-turbo-zh-q5_0.bin")),
        .init(id: "w-zh-turbo-q8",  name: "Belle Whisper Turbo ZH q8", task: .stt, lang: .chinese, bytes: 874_000_000,
              url: hf("uosx/Belle-whisper-large-v3-turbo-zh-ggml-quantized", "ggml-belle-large-v3-turbo-zh-q8_0.bin")),
        .init(id: "w-zh-turbo",     name: "Belle Whisper Turbo ZH",    task: .stt, lang: .chinese, bytes: 1_625_000_000,
              url: hf("BELLE-2/Belle-whisper-large-v3-turbo-zh-ggml", "ggml-model.bin")),
        // Japanese — Kotoba (distil Large-v3).
        .init(id: "w-ja-kotoba-q5", name: "Kotoba Whisper JA q5",      task: .stt, lang: .japanese, bytes: 538_000_000,
              url: hf("kotoba-tech/kotoba-whisper-v2.0-ggml", "ggml-kotoba-whisper-v2.0-q5_0.bin")),
        .init(id: "w-ja-kotoba",    name: "Kotoba Whisper JA",         task: .stt, lang: .japanese, bytes: 1_520_000_000,
              url: hf("kotoba-tech/kotoba-whisper-v2.0-ggml", "ggml-kotoba-whisper-v2.0.bin")),
        // English — official Distil-Whisper Large-v3.5.
        .init(id: "w-en-distil35",  name: "Distil Whisper EN v3.5",    task: .stt, lang: .english, bytes: 1_520_000_000,
              url: hf("distil-whisper/distil-large-v3.5-ggml", "ggml-model.bin")),
        // Portuguese (BR) — distil Large-v3 fine-tune.
        .init(id: "w-pt-distil-q5", name: "Distil Whisper PT-BR q5",   task: .stt, lang: .portuguese, bytes: 538_000_000,
              url: hf("lucasparis1103/distil-whisper-large-v3-ptbr-ggml", "ggml-distil-large-v3-ptbr-q5_0.bin")),
        // French — distil Large-v3 fine-tune.
        .init(id: "w-fr-distil-q5", name: "Distil Whisper FR q5",      task: .stt, lang: .french, bytes: 791_000_000,
              url: hf("Pomni/whisper-large-v3-french-distil-dec16-GGML-allquants", "ggml-large-v3-french-distil-dec16-q5_0.bin")),
        // TTS agora é o PocketTTS (FluidAudio), que baixa os próprios modelos.
    ]

    private static func hf(_ repo: String, _ file: String) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file)")!
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
}
