import Foundation

/// Which engine turns speech into text, and which turns text into speech.
///
/// Both are stored as a raw string in `UserDefaults` because that is what the
/// Settings `Picker` binds to. Everything that *reads* them goes through these
/// enums rather than comparing string literals of its own — the previous shape
/// spread nine such comparisons over four files, including one written as a
/// negation (`!= "model" && != "server" && != "endpoint"`) that silently decided
/// what a new engine would behave like. Adding `endpoint` to STT had to touch
/// five separate boolean expressions; adding a case here touches none.
///
/// The questions the call sites actually ask are answered here as properties,
/// so a new engine declares its own behaviour instead of being inferred from
/// the list of the others.
enum STTEngine: String, CaseIterable, Identifiable {
    /// Apple's `SFSpeechRecognizer`.
    case native
    /// Whisper running on the device.
    case model
    /// The Odysseus server's own `/api/stt/*`.
    case server
    /// A speech endpoint the user configured themselves.
    case endpoint

    static let key = "voice.stt.engine"

    /// An unset or unrecognised value is the native engine — the one that needs
    /// nothing configured and always exists.
    static var current: STTEngine {
        STTEngine(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .native
    }

    var id: String { rawValue }

    /// True only for Apple's recognizer, the one engine that reports a
    /// transcript while the user is still talking. Everything else transcribes
    /// a finished recording, so the voice loop has to end the turn on loudness
    /// instead of on the transcript going quiet.
    var hasLivePartials: Bool { self == .native }

    /// Every other engine transcribes a finished recording, so it needs the raw
    /// buffer rather than Apple's live stream.
    var needsRawCapture: Bool { self != .native }

    /// Only Apple's engine goes through `SFSpeechRecognizer`, so only it needs
    /// speech-recognition authorization on top of the microphone.
    var needsSpeechAuthorization: Bool { self == .native }

    var label: String {
        switch self {
        case .native:   return L("Nativo iOS")
        case .model:    return L("Modelo on-device")
        case .server:   return L("Servidor")
        case .endpoint: return L("Endpoint próprio")
        }
    }
}

enum TTSEngine: String, CaseIterable {
    /// Apple's `AVSpeechSynthesizer`.
    case native
    /// FluidAudio PocketTTS, on the Neural Engine.
    case neural
    /// The Odysseus server's own `/api/tts/synthesize`.
    case server
    /// A synthesis endpoint the user configured themselves.
    case endpoint

    static let key = "voice.tts.engine"

    static var current: TTSEngine {
        TTSEngine(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .native
    }

    /// Engines that synthesize over the network, and so can have the next
    /// sentence fetched while the current one is still playing. The native
    /// voice makes no request, and the neural one runs on the Neural Engine
    /// where a second concurrent synthesis competes with the one being played
    /// rather than hiding behind it.
    var isNetwork: Bool { self == .server || self == .endpoint }

    /// Only the user's own endpoint streams: the Odysseus route answers in one
    /// piece, and the two on-device engines have nothing to stream from.
    var canStream: Bool { self == .endpoint }

    /// What the trace calls this engine. Kept as its own property so the log
    /// vocabulary does not drift when a case is renamed.
    var logName: String {
        switch self {
        case .native:   return "nativo"
        case .neural:   return "neural"
        case .server:   return "servidor"
        case .endpoint: return "endpoint"
        }
    }
}
