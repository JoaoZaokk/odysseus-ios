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

    // MARK: - Streaming queue
    //
    // A reply is spoken sentence by sentence as the model writes it, instead of
    // waiting for the whole thing: the old path called toggle() once the stream
    // had finished, so time-to-first-word was the model's entire generation plus
    // a full synthesis of the result.

    private var chunks: [String] = []
    private var chunkID: String?
    /// True once the caller promises no further chunks, so the finish callback
    /// waits for the last one instead of firing between sentences.
    private var chunkClosed = false
    private var speakingChunk = false
    /// Reply whose queue was abandoned after a synthesis failure. Later
    /// sentences for it are dropped rather than retried: with a dead endpoint
    /// every one of them would fail the same way, publishing one error per
    /// sentence for the rest of the reply.
    private var failedChunkID: String?
    /// Synthesis started for the sentence at the head of `chunks`, before its
    /// turn to play arrives.
    ///
    /// This holds the *task*, not the finished bytes, and that distinction is
    /// the whole design. Holding bytes meant a sentence whose turn came while
    /// its request was still in flight found nothing ready and fired a second,
    /// duplicate request — most likely on exactly the short sentences ("Sim.",
    /// "Claro.") that finish playing before a round trip completes. Holding the
    /// task lets that case await the one request already running.
    ///
    /// Carries the turn, the exact text and the engine, so a queue that moved
    /// on — or an engine switched mid-reply — cannot consume the wrong audio.
    private var pendingSynthesis: (id: String, text: String, engine: String, task: Task<Data, Error>)?

    /// Plays audio that is still arriving. Used for the sentence that has
    /// nothing prefetched behind it — in practice the first of a reply, which is
    /// the only one whose round trip the user actually waits through.
    private let streamPlayer = PCMStreamPlayer()

    /// Streaming playback is opt-out, and only where it can pay: the hands-free
    /// conversation (`duplexSession`) against the user's own endpoint. Reading a
    /// single chat message aloud has no queue behind it and no barge-in, so the
    /// simpler buffered path stays there.
    private var streamingAllowed: Bool {
        UserDefaults.standard.object(forKey: "voice.tts.streaming") as? Bool ?? true
    }
    private var canStream: Bool { duplexSession && streamingAllowed && useEndpoint }

    /// True while a queued reply is being spoken — the voice loop uses it to arm
    /// barge-in the moment real audio starts, not before.
    var isSpeakingQueue: Bool { speakingChunk }

    /// Whether `text` still says anything once markdown is stripped. Callers
    /// that change state before queueing (the voice loop enters `.speaking` and
    /// reconfigures the audio session) must ask first: a sentence made only of
    /// markup — a fence, a bare `**`, a horizontal rule — is dropped by
    /// `enqueue`, which left the loop speaking with an empty queue and no
    /// `chunkID`, so `closeQueue` could never end the turn.
    nonisolated static func isSpeakable(_ text: String) -> Bool { !strip(text).isEmpty }

    /// What the engines will actually be asked to say. Exposed for tests; the
    /// speaking paths all go through `strip` themselves.
    nonisolated static func spokenText(_ text: String) -> String { strip(text) }

    /// Appends one sentence to the current reply's queue. The first call for an
    /// id starts it; later calls extend it.
    func enqueue(_ text: String, id: String) {
        guard failedChunkID != id else { return }   // this reply's TTS already died
        let clean = Self.strip(text)
        guard !clean.isEmpty else { return }
        if chunkID != id {
            clearQueue()
            chunkID = id
            chunkClosed = false
        }
        chunks.append(clean)
        pump()
        // pump() bails out while a sentence is playing, so without this the
        // sentence that just arrived would not begin synthesizing until the
        // current one finished — exactly the gap prefetching removes.
        if let cur = chunkID { prefetchNext(id: cur) }
    }

    /// No more sentences are coming for `id`. Fires the finish callback now if
    /// everything queued has already been spoken.
    func closeQueue(id: String) {
        guard chunkID == id else { return }
        chunkClosed = true
        if !speakingChunk && chunks.isEmpty { finished() }
    }

    private func clearQueue() {
        streamPlayer.onFinished = nil
        streamPlayer.onFirstAudio = nil
        streamPlayer.onInterrupted = nil
        streamPlayer.stop()
        chunks.removeAll()
        chunkID = nil
        chunkClosed = false
        speakingChunk = false
        failedChunkID = nil
        discardPrefetch()
    }

    /// Drops the speculative request. Anything that invalidates the queue has
    /// to call this, or a later sentence could consume audio belonging to a
    /// turn that is already over.
    private func discardPrefetch() {
        pendingSynthesis?.task.cancel()
        pendingSynthesis = nil
    }

    /// Local failures that never came from the network, so `isCancellation`
    /// correctly reports false for them.
    private enum Failure: LocalizedError {
        case noAPI
        /// The audio graph was torn down by a call or a route change.
        case interrupted
        /// The endpoint accepted the request and then sent nothing. Distinct
        /// from a transport error: there is nothing to retry against.
        case silent

        var errorDescription: String? {
            switch self {
            case .noAPI:       return nil
            case .interrupted: return L("A reprodução do áudio foi interrompida.")
            case .silent:      return L("O endpoint aceitou o pedido e não enviou áudio.")
            }
        }
    }

    /// One sentence failed to synthesize. Abandons the rest of that reply's
    /// queue and publishes the reason.
    ///
    /// The failure paths used to only set `neuralError`, leaving `speakingChunk`
    /// true forever: `pump()` was gated on it, so no later sentence was ever
    /// dispatched, and `closeQueue()` — which only fires the finish callback
    /// when `!speakingChunk` — became a permanent no-op. The turn could then
    /// never end on its own.
    private func chunkFailed(_ error: Error, id: String, _ message: @autoclosure () -> String) {
        preparingID = nil
        guard !isCancellation(error) else { return }
        if chunkID == id {
            chunks.removeAll()
            chunkID = nil
            chunkClosed = false
            speakingChunk = false
            failedChunkID = id
            discardPrefetch()
        }
        neuralError = message()
    }

    private func pump() {
        guard !speakingChunk, !chunks.isEmpty, let id = chunkID else { return }
        speakingChunk = true
        let next = chunks.removeFirst()
        if let p = pendingSynthesis, p.id == id, p.text == next, p.engine == engineName {
            // Already synthesized, or still in flight — either way, wait on the
            // request that is already running rather than issuing a second one.
            pendingSynthesis = nil
            VoiceLog.log("tts.toca", "motor=\(engineName) PREFETCH restam=\(chunks.count) \"\(next.prefix(40))\"")
            preparingID = id
            neuralTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let data = try await p.task.value
                    // The turn can end while this is awaited (barge-in, stop).
                    guard self.chunkID == id else { self.preparingID = nil; return }
                    self.play(data, id: id)
                } catch {
                    self.chunkFailed(error, id: id, self.msg(error))
                }
            }
        } else {
            // Whatever was being prefetched is not what plays next.
            discardPrefetch()
            // Nothing ready means this sentence would otherwise be a full round
            // trip of silence, so it is the one worth streaming. A sentence that
            // *did* have a prefetch waiting starts instantly from memory, which
            // no stream can beat.
            let streaming = canStream
            VoiceLog.log("tts.toca", "motor=\(engineName)\(streaming ? " STREAM" : "") restam=\(chunks.count) \"\(next.prefix(40))\"")
            if streaming { speakStreaming(next, id: id) } else { dispatchSpeak(next, id: id) }
        }
        prefetchNext(id: id)
    }

    /// Starts synthesizing the sentence that will play next, while the current
    /// one is still playing.
    ///
    /// The sentence queue removed the wait for the *whole* reply, but left one
    /// full network round trip of dead air at every sentence boundary — the
    /// next request only began once the previous sentence had finished playing.
    ///
    /// Network engines only: the native voice makes no request, and the neural
    /// one runs on the Neural Engine, where a second concurrent synthesis would
    /// compete with the one being played rather than hide behind it.
    private func prefetchNext(id: String) {
        guard useEndpoint || useServer else { return }
        guard pendingSynthesis == nil, let text = chunks.first else { return }
        let engine = engineName
        let task = Task<Data, Error> { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.synthesizeOverNetwork(text)
        }
        pendingSynthesis = (id: id, text: text, engine: engine, task: task)
        VoiceLog.log("tts.prefetch", "iniciada \"\(text.prefix(40))\"")
    }

    private func synthesizeOverNetwork(_ clean: String) async throws -> Data {
        // Timed because "the voice is slow" is otherwise unfalsifiable: this
        // number against the `p.duration` logged at playback says whether the
        // engine is slower than speech itself — the only case where a deeper
        // prefetch would buy anything.
        let t0 = Date()
        let data: Data
        if useEndpoint {
            data = try await VoiceEndpoint.synthesize(clean)
        } else {
            guard let api else { throw Failure.noAPI }
            data = try await api.synthesizeSpeech(clean)
        }
        VoiceLog.log("tts.sintetizou", String(format: "%.0f ms — %d chars — %d KB",
                                              Date().timeIntervalSince(t0) * 1000,
                                              clean.count, data.count / 1024))
        return data
    }

    /// Common tail of every engine that produces a finished audio buffer.
    private func play(_ data: Data, id: String) {
        do {
            activateTTSSession()
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            player = p
            preparingID = nil
            speakingID = id
            VoiceLog.log("tts.áudio", String(format: "%.1f s", p.duration))
            p.play()
        } catch {
            chunkFailed(error, id: id, msg(error))
        }
    }

    private var engineName: String {
        if useEndpoint { return "endpoint" }
        if useServer { return "servidor" }
        if useNeural { return "neural" }
        return "nativo"
    }

    /// Puts the audio session into the play-and-record configuration the
    /// barge-in monitor needs, before any audio exists. Called by the voice loop
    /// so echo cancellation is set up ahead of the first spoken sentence rather
    /// than after the first network round trip.
    func prepareDuplexSession() {
        activateTTSSession()
        #if os(iOS)
        let s = AVAudioSession.sharedInstance()
        VoiceLog.log("sessão", "categoria=\(s.category.rawValue) modo=\(s.mode.rawValue) duplex=\(duplexSession)")
        #endif
    }

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
    /// Releases the turn if the stream never delivers a first byte. See
    /// `speakStreaming`.
    private var streamWatchdog: Task<Void, Never>?

    var useNeural: Bool { UserDefaults.standard.string(forKey: "voice.tts.engine") == "neural" }
    var useServer: Bool { UserDefaults.standard.string(forKey: "voice.tts.engine") == "server" }
    /// A synthesis endpoint the user configured themselves (URL + key + model).
    var useEndpoint: Bool { UserDefaults.standard.string(forKey: "voice.tts.engine") == "endpoint" }
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
        dispatchSpeak(clean, id: id)
    }

    /// Settings' "test voice" button. Deliberately not `toggle`: `toggle` takes
    /// the buffered path, so the test used to pass green against an endpoint
    /// that cannot serve `response_format: "wav"` or whose WAV the decoder
    /// rejects — and then the actual conversation was silent, with nothing in
    /// Settings having said so. A test that does not exercise the path the
    /// feature uses is worse than no test, so this takes whichever path the
    /// hands-free loop would take with the current settings.
    func toggleTest(_ text: String, id: String) {
        if speakingID == id || preparingID == id { stop(); return }
        stop()
        let clean = Self.strip(text)
        guard !clean.isEmpty else { return }
        if streamingAllowed && useEndpoint { speakStreaming(clean, id: id) }
        else { dispatchSpeak(clean, id: id) }
    }

    /// Routes already-stripped text to the configured engine.
    private func dispatchSpeak(_ clean: String, id: String) {
        if useEndpoint { speakEndpoint(clean, id: id) }
        else if useServer { speakServer(clean, id: id) }
        else if useNeural { speakNeural(clean, id: id) }
        else { speakNative(clean, id: id) }
    }

    /// Loads what the server's TTS service reports (for the Settings footer).
    func loadServerInfo() async {
        guard let api else { return }
        serverStats = await api.ttsStats()
    }

    func stop() {
        clearQueue()
        neuralTask?.cancel(); neuralTask = nil
        streamWatchdog?.cancel(); streamWatchdog = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player?.stop(); player = nil
        streamPlayer.onFinished = nil
        streamPlayer.onFirstAudio = nil
        streamPlayer.stop()
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
            } catch {
                chunkFailed(error, id: id, msg(error))
            }
        }
    }

    // MARK: - Server (/api/tts/synthesize)

    private func speakServer(_ clean: String, id: String) {
        guard let api else {
            // Synchronous bail-out: still has to release the queue, or the turn
            // hangs exactly like an async failure would.
            chunkFailed(Failure.noAPI, id: id, L("Servidor de voz indisponível."))
            return
        }
        preparingID = id
        neuralError = nil
        neuralTask = Task {
            do {
                let data = try await api.synthesizeSpeech(clean)
                if Task.isCancelled { preparingID = nil; return }
                play(data, id: id)
            } catch {
                chunkFailed(error, id: id, L("TTS do servidor falhou: %@", msg(error)))
            }
        }
    }

    /// Plays one sentence as it is synthesized, instead of after.
    ///
    /// The turn is guarded at every await: `chunkID` changing means barge-in or
    /// a new reply arrived while bytes were in flight, and continuing would
    /// schedule audio from a turn that is already over.
    ///
    /// A stream that ends without ever producing audio is a failure, not a
    /// silent success — some gateways answer 200 with an empty body, and
    /// treating that as "spoke it" would advance the queue past a sentence
    /// nobody heard.
    private func speakStreaming(_ clean: String, id: String) {
        preparingID = id
        neuralError = nil
        streamPlayer.onFirstAudio = { [weak self] in
            guard let self, self.chunkID == id else { return }
            self.preparingID = nil
            self.speakingID = id
        }
        streamPlayer.onFinished = { [weak self] in
            guard let self, self.chunkID == id else { return }
            self.streamWatchdog?.cancel()
            self.finished()
        }
        // A call or a route change tears the graph down without delivering the
        // completion callbacks the queue is waiting on. That is a failure of
        // this sentence, not the end of it.
        streamPlayer.onInterrupted = { [weak self] in
            guard let self, self.chunkID == id else { return }
            self.streamWatchdog?.cancel()
            self.neuralTask?.cancel()
            self.chunkFailed(Failure.interrupted, id: id, self.msg(Failure.interrupted))
        }
        // `pump` has already set `speakingChunk`, and only a completion or a
        // failure clears it. A socket that accepts the request and then says
        // nothing would park the conversation in .speaking with the mic shut,
        // so silence gets a deadline. 25 s is far outside the measured cold
        // path (1642 ms to first audio).
        streamWatchdog?.cancel()
        streamWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25 * NSEC_PER_SEC)
            guard !Task.isCancelled, let self, self.chunkID == id,
                  self.preparingID == id else { return }
            VoiceLog.log("tts.stream", "sem áudio em 25 s — liberando o turno")
            self.neuralTask?.cancel()
            self.streamPlayer.stop()
            self.chunkFailed(Failure.silent, id: id, self.msg(Failure.silent))
        }
        let t0 = Date()
        neuralTask = Task { [weak self] in
            guard let self else { return }
            var decoder = WAVStreamDecoder()
            var opened = false
            var frameBytes = 0
            do {
                for try await chunk in try VoiceEndpoint.synthesizeStreaming(clean) {
                    if Task.isCancelled { return }
                    guard self.chunkID == id else { return }
                    let frames = try decoder.append(chunk)
                    guard let f = decoder.format else { continue }
                    if !opened {
                        try self.streamPlayer.begin(sampleRate: f.sampleRate)
                        opened = true
                        self.streamWatchdog?.cancel()
                        VoiceLog.log("tts.stream", String(format: "1º áudio em %.0f ms — %d chars",
                                                          Date().timeIntervalSince(t0) * 1000, clean.count))
                    }
                    guard !frames.isEmpty else { continue }
                    frameBytes += frames.count
                    self.streamPlayer.schedule(WAVStreamDecoder.monoFloat(frames, f))
                }
                if Task.isCancelled { return }
                guard self.chunkID == id else { return }
                guard opened, frameBytes > 0 else { throw VoiceEndpoint.Failure.noText(body: "") }
                VoiceLog.log("tts.stream", String(format: "fim — %.0f ms — %d KB",
                                                  Date().timeIntervalSince(t0) * 1000, frameBytes / 1024))
                self.streamPlayer.endOfStream()
            } catch {
                self.streamWatchdog?.cancel()
                self.streamPlayer.stop()
                self.chunkFailed(error, id: id, self.msg(error))
            }
        }
    }

    /// Same shape as `speakServer`, against the user's own endpoint. Failures
    /// carry the server's response body so a 401 and a 404 are distinguishable
    /// without a laptop.
    private func speakEndpoint(_ clean: String, id: String) {
        preparingID = id
        neuralError = nil
        neuralTask = Task {
            do {
                let data = try await VoiceEndpoint.synthesize(clean)
                if Task.isCancelled { preparingID = nil; return }
                play(data, id: id)
            } catch {
                chunkFailed(error, id: id, msg(error))
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

    /// URLSession reports a cancelled request as `URLError.cancelled`, not
    /// `CancellationError`, so `catch is CancellationError` never matched and
    /// stopping playback published a spurious error — which the voice loop then
    /// treated as "TTS died", advancing the turn a second time.
    private func isCancellation(_ e: Error) -> Bool {
        if e is CancellationError { return true }
        return (e as? URLError)?.code == .cancelled
    }

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

    nonisolated private static func strip(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "```[\\s\\S]*?```", with: L(" (bloco de código) "), options: .regularExpression)
        t = t.replacingOccurrences(of: "`([^`]*)`", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\*\\*([^*]*)\\*\\*", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "[*_#>]", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
        // Table rows arrive as chunks of their own (the sentence cutter breaks on
        // newlines) and were being read out verbatim, pipes and all. Nobody hit
        // it until a reply came back with a comparison table, and then the voice
        // spent half a minute reciting "Duração 4 anos 1914-1918 6 anos". A
        // separator row carries no words at all; a data row is a list of cells,
        // so it is spoken as one.
        if t.contains("|") {
            let cells = t.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let isRule = !cells.isEmpty && cells.allSatisfy { cell in
                cell.allSatisfy { $0 == "-" || $0 == ":" }
            }
            t = isRule ? "" : cells.joined(separator: ", ")
        }
        let cleaned = t.trimmingCharacters(in: .whitespacesAndNewlines)
        // Whatever is left with no letter and no digit is markup the rules above
        // didn't recognize: an unclosed code fence (the fence rule needs both
        // ends, so a lone ``` survives as a stray backtick), a horizontal rule,
        // a bare bullet. Speaking it produces a garbage utterance — and it also
        // defeats `isSpeakable`, letting the voice loop commit to .speaking for
        // a chunk that says nothing.
        return cleaned.contains(where: { $0.isLetter || $0.isNumber }) ? cleaned : ""
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
        if speakingChunk {
            speakingChunk = false
            // More sentences ready: keep going without telling the caller the
            // reply is over.
            if !chunks.isEmpty { pump(); return }
            // Nothing queued but the model is still writing — wait for the next
            // sentence rather than ending the turn mid-reply.
            guard chunkClosed else { return }
            chunkID = nil
        }
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
