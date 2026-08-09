import AVFoundation
import SwiftUI
import FluidAudio

/// Text-to-speech with two engines, chosen in Settings:
/// - **native**: Apple `AVSpeechSynthesizer` (instant, robotic).
/// - **neural**: a FluidAudio **PocketTTS** language pack (CoreML/ANE, much more
///   natural). Downloads ~550 MB on first use, then synthesizes on-device.
///
/// Both follow the app's active language (`LocalizationManager`), not a fixed
/// locale — PocketTTS only ships 6 packs, so any other language falls back to
/// the native engine, which resolves the system's own voice for that language.
@MainActor
final class SpeechManager: NSObject, ObservableObject {
    static let shared = SpeechManager()

    @Published private(set) var speakingID: String?
    @Published private(set) var preparingID: String?   // neural: downloading/synthesizing
    @Published var neuralReady = false
    @Published var neuralError: String?

    private let synth = AVSpeechSynthesizer()
    private var language: String { LocalizationManager.shared.active.speechCode }

    // Neural (PocketTTS) — the loaded pack, and which language it was loaded for
    // (so switching the app language reloads instead of speaking the old one).
    private var pocket: PocketTtsManager?
    private var pocketLanguage: PocketTtsLanguage?
    private var player: AVAudioPlayer?
    private var neuralTask: Task<Void, Never>?

    /// Neural only applies when PocketTTS actually ships a pack for the active
    /// language; otherwise the native engine handles it.
    var useNeural: Bool {
        UserDefaults.standard.string(forKey: "voice.tts.engine") == "neural" && Self.pocketPack() != nil
    }
    /// The stored voice belongs to the Portuguese pack — the voice IDs differ per
    /// pack, so any other language uses that pack's own default.
    private var neuralVoice: String? {
        guard Self.pocketPack() == .portuguese else { return nil }
        return UserDefaults.standard.string(forKey: "voice.tts.pocketVoice") ?? "alba"
    }

    override init() { super.init(); synth.delegate = self }

    func isSpeaking(_ id: String) -> Bool { speakingID == id }
    func isPreparing(_ id: String) -> Bool { preparingID == id }

    /// Speak `text` for message `id`, or stop if it's already active (toggle).
    func toggle(_ text: String, id: String) {
        if speakingID == id || preparingID == id { stop(); return }
        stop()
        let clean = Self.strip(text)
        guard !clean.isEmpty else { return }
        if useNeural { speakNeural(clean, id: id) } else { speakNative(clean, id: id) }
    }

    func stop() {
        neuralTask?.cancel(); neuralTask = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player?.stop(); player = nil
        speakingID = nil; preparingID = nil
    }

    // MARK: - Native (AVSpeechSynthesizer)

    private func speakNative(_ clean: String, id: String) {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let u = AVSpeechUtterance(string: clean)
        u.voice = Self.bestVoice(for: language)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        speakingID = id
        synth.speak(u)
    }

    // MARK: - Neural (PocketTTS)

    /// Proactively downloads + loads the PocketTTS pt model (so the first 🔊 isn't
    /// a multi-minute wait). Safe to call repeatedly.
    func prepareNeural() {
        guard preparingID == nil, pocket == nil || pocketLanguage != Self.pocketPack() else { return }
        neuralReady = false
        preparingID = "__prepare__"
        neuralError = nil
        neuralTask = Task {
            do { _ = try await ensurePocket(); neuralReady = true }
            catch { neuralError = msg(error) }
            if preparingID == "__prepare__" { preparingID = nil }
        }
    }

    private func speakNeural(_ clean: String, id: String) {
        preparingID = id
        neuralError = nil
        let voice = neuralVoice
        neuralTask = Task {
            do {
                let m = try await ensurePocket()
                neuralReady = true
                let wav = try await m.synthesize(text: clean, voice: voice)
                if Task.isCancelled { preparingID = nil; return }
                #if os(iOS)
                try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
                try? AVAudioSession.sharedInstance().setActive(true)
                #endif
                let p = try AVAudioPlayer(data: wav)
                p.delegate = self
                player = p
                preparingID = nil
                speakingID = id
                p.play()
            } catch is CancellationError {
                preparingID = nil
            } catch {
                neuralError = msg(error)
                preparingID = nil
            }
        }
    }

    private func ensurePocket() async throws -> PocketTtsManager {
        let pack = Self.pocketPack() ?? .english
        if let pocket, pocketLanguage == pack { return pocket }
        let m = PocketTtsManager(language: pack, precision: .int8)
        try await m.initialize()
        pocket = m
        pocketLanguage = pack
        return m
    }

    /// The PocketTTS pack for the app's active language, or nil when there is
    /// none (PocketTTS only ships en/fr/de/it/pt/es).
    private static func pocketPack() -> PocketTtsLanguage? {
        switch LocalizationManager.shared.active {
        case .en:                       return .english
        case .fr:                       return .french24L
        case .de, .deAT, .deCH:         return .german
        case .it:                       return .italian
        case .ptBR:                     return .portuguese
        case .es:                       return .spanish
        default:                        return nil
        }
    }

    private func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? e.localizedDescription }

    // MARK: - Helpers

    /// Best installed voice for `lang`, preferring an exact region match
    /// ("pt-BR") over a same-language one ("pt-PT" for "pt"), and higher quality
    /// within each. Returns nil when the device has no voice at all for the
    /// language — `AVSpeechUtterance` then falls back to the system default.
    private static func bestVoice(for lang: String) -> AVSpeechSynthesisVoice? {
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            switch v.quality { case .premium: return 3; case .enhanced: return 2; default: return 1 }
        }
        let base = lang.split(separator: "-").first.map(String.init) ?? lang
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let exact = voices.filter { $0.language.caseInsensitiveCompare(lang) == .orderedSame }
        let sameLanguage = voices.filter { $0.language.lowercased().hasPrefix(base.lowercased() + "-") }
        let candidates = (exact.isEmpty ? sameLanguage : exact).sorted { rank($0) > rank($1) }
        return candidates.first ?? AVSpeechSynthesisVoice(language: lang) ?? AVSpeechSynthesisVoice(language: base)
    }

    private static func strip(_ s: String) -> String {
        var t = s
        // Spoken out loud, so it follows the app language like everything else.
        let codeBlock = L("(bloco de código)")
        t = t.replacingOccurrences(of: "```[\\s\\S]*?```", with: " \(codeBlock) ", options: .regularExpression)
        t = t.replacingOccurrences(of: "`([^`]*)`", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\*\\*([^*]*)\\*\\*", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "[*_#>]", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.speakingID = nil }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.speakingID = nil }
    }
}

extension SpeechManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.speakingID = nil }
    }
}

/// The PocketTTS Portuguese voices (from FluidInference/pocket-tts-coreml).
enum PocketVoices {
    static let portuguese = [
        "alba", "anna", "azelma", "bill_boerst", "caro_davy", "charles", "cosette",
        "eponine", "estelle", "eve", "fantine", "george", "giovanni", "jane", "javert",
        "jean", "juergen", "lola", "marius", "mary", "michael", "paul", "peter_yearsley",
        "rafael", "stuart_bell", "vera",
    ]
}
