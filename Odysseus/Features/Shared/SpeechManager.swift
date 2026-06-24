import AVFoundation
import SwiftUI
import FluidAudio

/// Text-to-speech with two engines, chosen in Settings:
/// - **native**: Apple `AVSpeechSynthesizer` (pt-BR, instant, robotic).
/// - **neural**: FluidAudio **PocketTTS** Portuguese pack (CoreML/ANE, much more
///   natural). Downloads ~550 MB on first use, then synthesizes on-device.
@MainActor
final class SpeechManager: NSObject, ObservableObject {
    static let shared = SpeechManager()

    @Published private(set) var speakingID: String?
    @Published private(set) var preparingID: String?   // neural: downloading/synthesizing
    @Published var neuralReady = false
    @Published var neuralError: String?

    private let synth = AVSpeechSynthesizer()
    private let language = "pt-BR"

    // Neural (PocketTTS pt-BR)
    private var pocket: PocketTtsManager?
    private var player: AVAudioPlayer?
    private var neuralTask: Task<Void, Never>?

    var useNeural: Bool { UserDefaults.standard.string(forKey: "voice.tts.engine") == "neural" }
    private var neuralVoice: String { UserDefaults.standard.string(forKey: "voice.tts.pocketVoice") ?? "alba" }

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
        guard pocket == nil, preparingID == nil else { return }
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
        if let pocket { return pocket }
        let m = PocketTtsManager(language: .portuguese, precision: .int8)
        try await m.initialize()
        pocket = m
        return m
    }

    private func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? e.localizedDescription }

    // MARK: - Helpers

    private static func bestVoice(for lang: String) -> AVSpeechSynthesisVoice? {
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            switch v.quality { case .premium: return 3; case .enhanced: return 2; default: return 1 }
        }
        let exact = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.caseInsensitiveCompare(lang) == .orderedSame }
            .sorted { rank($0) > rank($1) }
        return exact.first ?? AVSpeechSynthesisVoice(language: lang)
    }

    private static func strip(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "```[\\s\\S]*?```", with: " (bloco de código) ", options: .regularExpression)
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
