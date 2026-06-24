import Foundation

enum VoiceTask: String, Codable { case stt, tts }

enum VoiceLang: String, Codable, CaseIterable {
    case bilingual, portuguese, english
    var label: String {
        switch self {
        case .bilingual: "Bilíngue"
        case .portuguese: "Português"
        case .english: "Inglês"
        }
    }
    var flag: String {
        switch self {
        case .bilingual: "🌐"; case .portuguese: "🇧🇷"; case .english: "🇺🇸"
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
    var filename: String { url.lastPathComponent }

    /// Size bucket the user asked to group by.
    enum Bucket: String, CaseIterable { case mb500 = "Até 500 MB", gb1 = "Até 1 GB", gb2 = "Até 2 GB", gb3 = "Até 3 GB" }
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

enum VoiceCatalog {
    private static func whisper(_ file: String) -> URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(file)")!
    }
    private static func kokoro(_ file: String) -> URL {
        URL(string: "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main/onnx/\(file)")!
    }

    static let all: [VoiceModel] = [
        // ── STT · Whisper (whisper.cpp GGUF) ──
        .init(id: "w-tiny",            name: "Whisper Tiny",            task: .stt, lang: .bilingual, bytes:  75_000_000, url: whisper("ggml-tiny.bin")),
        .init(id: "w-tiny-en",         name: "Whisper Tiny (EN)",       task: .stt, lang: .english,   bytes:  75_000_000, url: whisper("ggml-tiny.en.bin")),
        .init(id: "w-small-q5",        name: "Whisper Small q5",        task: .stt, lang: .bilingual, bytes: 181_000_000, url: whisper("ggml-small-q5_1.bin")),
        .init(id: "w-base",            name: "Whisper Base",            task: .stt, lang: .bilingual, bytes: 142_000_000, url: whisper("ggml-base.bin")),
        .init(id: "w-base-en",         name: "Whisper Base (EN)",       task: .stt, lang: .english,   bytes: 142_000_000, url: whisper("ggml-base.en.bin")),
        .init(id: "w-small",           name: "Whisper Small",           task: .stt, lang: .bilingual, bytes: 466_000_000, url: whisper("ggml-small.bin")),

        .init(id: "w-small-en",        name: "Whisper Small (EN)",      task: .stt, lang: .english,   bytes: 466_000_000, url: whisper("ggml-small.en.bin")),
        .init(id: "w-medium-q5",       name: "Whisper Medium q5",       task: .stt, lang: .bilingual, bytes: 539_000_000, url: whisper("ggml-medium-q5_0.bin")),
        .init(id: "w-medium-en-q5",    name: "Whisper Medium q5 (EN)",  task: .stt, lang: .english,   bytes: 539_000_000, url: whisper("ggml-medium.en-q5_0.bin")),
        .init(id: "w-turbo-q5",        name: "Whisper Large-v3 Turbo q5",task: .stt, lang: .bilingual, bytes: 574_000_000, url: whisper("ggml-large-v3-turbo-q5_0.bin")),
        .init(id: "w-largev2-q5",      name: "Whisper Large-v2 q5",     task: .stt, lang: .bilingual, bytes: 1_080_000_000, url: whisper("ggml-large-v2-q5_0.bin")),

        .init(id: "w-largev3-q5",      name: "Whisper Large-v3 q5",     task: .stt, lang: .bilingual, bytes: 1_080_000_000, url: whisper("ggml-large-v3-q5_0.bin")),
        .init(id: "w-medium",          name: "Whisper Medium",          task: .stt, lang: .bilingual, bytes: 1_530_000_000, url: whisper("ggml-medium.bin")),
        .init(id: "w-medium-en",       name: "Whisper Medium (EN)",     task: .stt, lang: .english,   bytes: 1_530_000_000, url: whisper("ggml-medium.en.bin")),
        .init(id: "w-turbo",           name: "Whisper Large-v3 Turbo",  task: .stt, lang: .bilingual, bytes: 1_620_000_000, url: whisper("ggml-large-v3-turbo.bin")),

        .init(id: "w-largev3",         name: "Whisper Large-v3",        task: .stt, lang: .bilingual, bytes: 3_100_000_000, url: whisper("ggml-large-v3.bin")),
        .init(id: "w-largev2",         name: "Whisper Large-v2",        task: .stt, lang: .bilingual, bytes: 3_090_000_000, url: whisper("ggml-large-v2.bin")),
        .init(id: "w-largev1",         name: "Whisper Large-v1",        task: .stt, lang: .bilingual, bytes: 3_090_000_000, url: whisper("ggml-large-v1.bin")),
        // TTS agora é o PocketTTS (FluidAudio), que baixa os próprios modelos.
    ]

    static func filtered(task: VoiceTask, lang: VoiceLang?) -> [VoiceModel] {
        all.filter { $0.task == task && (lang == nil || $0.lang == lang || $0.lang == .bilingual) }
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
