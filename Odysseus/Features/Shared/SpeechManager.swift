import AVFoundation
import SwiftUI
import FluidAudio
#if os(iOS)
import UIKit
#endif

/// Text-to-speech with three engines, chosen in Settings:
/// - **native**: Apple `AVSpeechSynthesizer`, in the app's UI language
///   (instant, robotic).
/// - **neural**: FluidAudio **PocketTTS** (CoreML/ANE, much more natural), in
///   the pack matching the app's UI language — Portuguese, English, Spanish,
///   French, German or Italian. ~550 MB per language, downloaded on first use
///   and then synthesized on-device. Any other UI language has no pack upstream
///   and falls back to the native voice.
/// - **server**: the Odysseus server's own `/api/tts/synthesize`. Nothing is
///   downloaded and nothing runs on the phone, but the voice and language are
///   whatever the server admin configured — the endpoint takes only the text.
@MainActor
final class SpeechManager: NSObject, ObservableObject {
    static let shared = SpeechManager()

    @Published private(set) var speakingID: String?
    @Published private(set) var preparingID: String?   // neural: downloading/synthesizing
    @Published var neuralReady = false
    @Published var neuralError: String?

    /// One-shot hook fired when an utterance finishes (or is cancelled) playing.
    /// The hands-free voice loop uses it to advance to the next turn.
    var onSpeechFinished: (() -> Void)?

    /// Injected at launch — lets the "server" TTS engine reach Odysseus.
    var api: APIClient?
    /// What the server's TTS service reports about itself, loaded on demand.
    /// Unlike Open WebUI, Odysseus exposes no voice list: `/api/tts/synthesize`
    /// takes only `{text, format}` and speaks with whatever the admin set, so
    /// this is shown to explain the voice rather than to choose one.
    @Published var serverStats: SpeechServiceStats?
    /// When true (hands-free voice mode), TTS uses a play-AND-record session so the
    /// barge-in monitor can listen while the assistant speaks.
    var duplexSession = false

    private func activateTTSSession() {
        #if os(iOS)
        let s = AVAudioSession.sharedInstance()
        if duplexSession {
            try? s.setCategory(.playAndRecord, mode: .voiceChat, options: [.duckOthers, .allowBluetoothA2DP])
            try? s.setActive(true)
            applyProximityRoute()
        } else {
            try? s.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? s.setActive(true)
        }
        #endif
    }

    /// In hands-free voice mode: loudspeaker when the phone is away from the ear,
    /// earpiece when held to it (driven by the proximity sensor). Call on each TTS
    /// start and whenever proximity changes.
    func applyProximityRoute() {
        #if os(iOS)
        guard duplexSession else { return }
        let near = UIDevice.current.proximityState
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(near ? .none : .speaker)
        #endif
    }

    private let synth = AVSpeechSynthesizer()
    /// Read fresh on every utterance — the user can change the app language at
    /// any time and the next 🔊 must follow it (a stored constant is what made
    /// English replies come out in a Portuguese voice).
    private var language: String { LocalizationManager.shared.active.speechCode }

    // Neural (PocketTTS). One manager per language pack — `pocketLanguage`
    // records which pack is loaded so switching the app language swaps it
    // instead of speaking German with the Portuguese weights.
    private var pocket: PocketTtsManager?
    private var pocketLanguage: PocketTtsLanguage?
    private var player: AVAudioPlayer?
    private var neuralTask: Task<Void, Never>?

    var useNeural: Bool { UserDefaults.standard.string(forKey: "voice.tts.engine") == "neural" }
    var useServer: Bool { UserDefaults.standard.string(forKey: "voice.tts.engine") == "server" }
    private var neuralVoice: String { UserDefaults.standard.string(forKey: "voice.tts.pocketVoice") ?? "alba" }
    // No server voice/model settings: the Odysseus synth endpoint takes neither.

    override init() { super.init(); synth.delegate = self }

    func isSpeaking(_ id: String) -> Bool { speakingID == id }
    func isPreparing(_ id: String) -> Bool { preparingID == id }

    /// Speak `text` for message `id`, or stop if it's already active (toggle).
    func toggle(_ text: String, id: String) {
        if speakingID == id || preparingID == id { stop(); return }
        stop()
        let clean = Self.strip(text)
        guard !clean.isEmpty else { return }
        if useServer { speakServer(clean, id: id) }
        else if useNeural { speakNeural(clean, id: id) }
        else { speakNative(clean, id: id) }
    }

    /// Loads what the server's TTS service reports (for the Settings footer).
    func loadServerInfo() async {
        guard let api else { return }
        serverStats = await api.ttsStats()
    }

    func stop() {
        neuralTask?.cancel(); neuralTask = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player?.stop(); player = nil
        speakingID = nil; preparingID = nil
    }

    // MARK: - Native (AVSpeechSynthesizer)

    private func speakNative(_ clean: String, id: String) {
        activateTTSSession()
        let u = AVSpeechUtterance(string: clean)
        u.voice = Self.bestVoice(for: language)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        speakingID = id
        synth.speak(u)
    }

    // MARK: - Neural (PocketTTS)

    /// The PocketTTS pack for the app's UI language, or nil when upstream ships
    /// none. Kyutai publishes six packs; everything else falls back to the
    /// native voice rather than reading, say, Japanese with Italian weights.
    static func pocketPack(for lang: AppLanguage) -> PocketTtsLanguage? {
        switch lang {
        case .ptBR:             return .portuguese
        case .en:               return .english
        case .es:               return .spanish
        case .fr:               return .french24L   // upstream ships only the 24-layer French pack
        case .de, .deAT, .deCH: return .german
        case .it:               return .italian
        default:                return nil
        }
    }

    /// True when the neural engine can actually speak the current UI language.
    var neuralAvailableForCurrentLanguage: Bool {
        Self.pocketPack(for: LocalizationManager.shared.active) != nil
    }

    /// Proactively downloads + loads the PocketTTS pack for the current language
    /// (so the first 🔊 isn't a multi-minute wait). Safe to call repeatedly.
    func prepareNeural() {
        guard preparingID == nil else { return }
        let lang = LocalizationManager.shared.active
        guard let pack = Self.pocketPack(for: lang) else {
            neuralError = L("Voz neural indisponível para %@ — usando a voz nativa.", lang.nativeName)
            return
        }
        guard pocket == nil || pocketLanguage != pack else { return }
        preparingID = "__prepare__"
        neuralError = nil
        neuralTask = Task {
            do { _ = try await ensurePocket(pack); neuralReady = true }
            catch { neuralError = msg(error) }
            if preparingID == "__prepare__" { preparingID = nil }
        }
    }

    private func speakNeural(_ clean: String, id: String) {
        let lang = LocalizationManager.shared.active
        // No pack for this language: say so once and still speak, natively.
        // Silently swapping engines would look like the neural setting is
        // ignored; refusing to speak at all would be worse.
        guard let pack = Self.pocketPack(for: lang) else {
            neuralError = L("Voz neural indisponível para %@ — usando a voz nativa.", lang.nativeName)
            speakNative(clean, id: id)
            return
        }
        preparingID = id
        neuralError = nil
        let voice = neuralVoice
        neuralTask = Task {
            do {
                let m = try await ensurePocket(pack)
                neuralReady = true
                let wav = try await m.synthesize(text: clean, voice: voice)
                if Task.isCancelled { preparingID = nil; return }
                activateTTSSession()
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

    // MARK: - Server (/api/tts/synthesize)

    private func speakServer(_ clean: String, id: String) {
        guard let api else { neuralError = L("Servidor de voz indisponível."); return }
        preparingID = id
        neuralError = nil
        neuralTask = Task {
            do {
                let data = try await api.synthesizeSpeech(clean)
                if Task.isCancelled { preparingID = nil; return }
                activateTTSSession()
                let p = try AVAudioPlayer(data: data)
                p.delegate = self
                player = p
                preparingID = nil
                speakingID = id
                p.play()
            } catch is CancellationError {
                preparingID = nil
            } catch {
                neuralError = L("TTS do servidor falhou: %@", msg(error))
                preparingID = nil
            }
        }
    }

    /// Drops the in-memory manager when its pack was deleted from disk, so the
    /// next 🔊 re-downloads instead of speaking from a half-freed cache.
    func forgetPack(_ pack: PocketTtsLanguage) {
        guard pocketLanguage == pack else { return }
        stop()
        pocket = nil
        pocketLanguage = nil
        neuralReady = false
    }

    /// Loads (downloading on first use) the manager for `pack`, reusing the
    /// cached one only when it's the same pack — each language is a separate
    /// ~550 MB download and a separate set of weights.
    private func ensurePocket(_ pack: PocketTtsLanguage) async throws -> PocketTtsManager {
        if let pocket, pocketLanguage == pack { return pocket }
        neuralReady = false
        let m = PocketTtsManager(language: pack, precision: .int8)
        try await m.initialize()
        // The cache only exists once FluidAudio has created it, so flag it after
        // the first load rather than up front.
        NeuralVoiceStore.excludeCacheFromBackup()
        pocket = m
        pocketLanguage = pack
        return m
    }

    private func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? e.localizedDescription }

    // MARK: - Helpers

    /// Best installed voice for `lang`, degrading region → language → nil.
    /// Returning nil is deliberate: AVSpeechSynthesizer then picks the system
    /// default, which is far better than reading e.g. Japanese with a Brazilian
    /// voice just because that identifier happened to be hard-coded.
    private static func bestVoice(for lang: String) -> AVSpeechSynthesisVoice? {
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            switch v.quality { case .premium: return 3; case .enhanced: return 2; default: return 1 }
        }
        let installed = AVSpeechSynthesisVoice.speechVoices()
        let exact = installed
            .filter { $0.language.caseInsensitiveCompare(lang) == .orderedSame }
            .sorted { rank($0) > rank($1) }
        if let v = exact.first { return v }

        // "de-AT" with no Austrian voice installed should still speak German,
        // not fall through to the system default (often English).
        let base = lang.split(separator: "-").first.map(String.init) ?? lang
        let sameLanguage = installed
            .filter { $0.language.lowercased().hasPrefix(base.lowercased() + "-") }
            .sorted { rank($0) > rank($1) }
        if let v = sameLanguage.first { return v }

        return AVSpeechSynthesisVoice(language: lang) ?? AVSpeechSynthesisVoice(language: base)
    }

    private static func strip(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "```[\\s\\S]*?```", with: L(" (bloco de código) "), options: .regularExpression)
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
        Task { @MainActor in self.finished() }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }
}

extension SpeechManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finished() }
    }
}

private extension SpeechManager {
    func finished() {
        speakingID = nil
        let cb = onSpeechFinished
        onSpeechFinished = nil
        cb?()
    }
}

/// The PocketTTS voices (from FluidInference/pocket-tts-coreml).
///
/// The same 26 names ship in **every** language pack — only the acoustic
/// embedding behind each name differs (verified against the repo tree: all of
/// `v2.1/{english,spanish,french_24l,german,italian,portuguese}/constants_bin/`
/// hold an identical set of `<voice>.safetensors`). So one list serves all
/// languages, and a voice the user picked keeps working after switching.
enum PocketVoices {
    static let all = [
        "alba", "anna", "azelma", "bill_boerst", "caro_davy", "charles", "cosette",
        "eponine", "estelle", "eve", "fantine", "george", "giovanni", "jane", "javert",
        "jean", "juergen", "lola", "marius", "mary", "michael", "paul", "peter_yearsley",
        "rafael", "stuart_bell", "vera",
    ]
}
