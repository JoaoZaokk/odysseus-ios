import AVFoundation
import SwiftUI
import FluidAudio
#if os(iOS)
import UIKit
#endif

/// Text-to-speech with four engines, chosen in Settings (see `TTSEngine`):
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
/// - **endpoint**: a synthesis service the user configured themselves (URL,
///   key, model — see `VoiceEndpoint`). The only one that can stream, so it is
///   also the only one whose first sentence starts before it finishes
///   synthesizing.
@MainActor
final class SpeechManager: NSObject, ObservableObject {
    static let shared = SpeechManager()

    /// Ids for the two utterances that belong to no message: the Settings
    /// screen's pack download and its "test voice" button. Both screens ask
    /// `isPreparing(_:)` about them, so the value has to be spelled the same in
    /// two files — as bare literals, one typo away from a spinner that never
    /// stops.
    static let prepareID = "__prepare__"
    static let testID = "__test__"

    @Published private(set) var speakingID: String?
    @Published private(set) var preparingID: String?   // neural: downloading/synthesizing
    @Published var neuralReady = false
    @Published var neuralError: String?

    /// One-shot hook fired when an utterance finishes (or is cancelled) playing.
    /// The hands-free voice loop uses it to advance to the next turn.
    var onSpeechFinished: (() -> Void)?

    /// Fired when a reply's queue is abandoned because a sentence could not be
    /// synthesized or played.
    ///
    /// The hands-free loop used to learn about that by subscribing to the
    /// `@Published neuralError` string, which is not a failure channel:
    /// `speakNeural`'s "no PocketTTS pack for this language" branch sets
    /// `neuralError` and then speaks anyway, natively. The loop read that as
    /// "TTS died" and reopened the microphone on top of the native voice —
    /// reachable from Settings with any of the 38 UI languages that have no
    /// pack. This fires only from `chunkFailed`, so it cannot be confused with
    /// text meant for the Settings screen.
    ///
    /// Unlike `onSpeechFinished` this is not one-shot: nothing consumes it, so
    /// it stays installed for the whole turn. Like the finish hook, it belongs
    /// to whoever set it — this class never clears either one.
    var onSpeechFailed: ((String) -> Void)?

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
    private var pendingSynthesis: (id: String, text: String, engine: TTSEngine, task: Task<Data, Error>)?

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
    private var canStream: Bool { duplexSession && streamingAllowed && TTSEngine.current.canStream }

    /// True while a queued reply is being spoken — the voice loop uses it to arm
    /// barge-in the moment real audio starts, not before.
    var isSpeakingQueue: Bool { speakingChunk }

    /// Appends one sentence to the current reply's queue. The first call for an
    /// id starts it; later calls extend it.
    func enqueue(_ text: String, id: String) {
        guard failedChunkID != id else { return }   // this reply's TTS already died
        let clean = SpokenText.strip(text)
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

    /// Silences the streaming player and drops its callbacks.
    ///
    /// One list, because it was written out twice — in `clearQueue` and again in
    /// `stop` — and the second copy had already lost `onInterrupted`, which only
    /// stayed harmless because `stop` happens to call `clearQueue` first.
    private func teardownStreamPlayer() {
        streamPlayer.onFinished = nil
        streamPlayer.onFirstAudio = nil
        streamPlayer.onInterrupted = nil
        streamPlayer.stop()
    }

    private func clearQueue() {
        teardownStreamPlayer()
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
        guard !error.isCancellation else { return }
        if chunkID == id {
            chunks.removeAll()
            chunkID = nil
            chunkClosed = false
            speakingChunk = false
            failedChunkID = id
            discardPrefetch()
        }
        let text = message()
        neuralError = text          // Settings screen
        onSpeechFailed?(text)       // the voice loop, which must not read the line above
    }

    private func pump() {
        guard !speakingChunk, !chunks.isEmpty, let id = chunkID else { return }
        speakingChunk = true
        let next = chunks.removeFirst()
        let engine = TTSEngine.current
        if let p = pendingSynthesis, p.id == id, p.text == next, p.engine == engine {
            // Already synthesized, or still in flight — either way, wait on the
            // request that is already running rather than issuing a second one.
            pendingSynthesis = nil
            VoiceLog.log("tts.toca", "motor=\(engine.logName) PREFETCH restam=\(chunks.count) \"\(next.prefix(40))\"")
            preparingID = id
            speechTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let data = try await p.task.value
                    // The turn can end while this is awaited (barge-in, stop).
                    guard self.chunkID == id else { self.preparingID = nil; return }
                    self.play(data, id: id)
                } catch {
                    self.chunkFailed(error, id: id, SettingsUI.msg(error))
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
            VoiceLog.log("tts.toca", "motor=\(engine.logName)\(streaming ? " STREAM" : "") restam=\(chunks.count) \"\(next.prefix(40))\"")
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
        let engine = TTSEngine.current
        guard engine.isNetwork else { return }
        guard pendingSynthesis == nil, let text = chunks.first else { return }
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
        switch TTSEngine.current {
        case .endpoint:
            data = try await VoiceEndpoint.synthesize(clean)
        case .server, .native, .neural:
            // Only `.server` reaches here — `prefetchNext` is gated on
            // `isNetwork` — but the two on-device engines have no synthesis
            // *over the network* to fall back to either way.
            guard let api else { throw Failure.noAPI }
            data = try await api.synthesizeSpeech(clean)
        }
        VoiceLog.log("tts.sintetizou", String(format: "%.0f ms — %d chars — %d KB",
                                              Date().timeIntervalSince(t0) * 1000,
                                              clean.count, data.count / 1024))
        return data
    }

    /// Common body of every engine that produces a finished audio buffer:
    /// claim the turn, run `produce`, hand the bytes to `play`.
    ///
    /// It exists because the neural, server and endpoint paths were three copies
    /// of this shape and had drifted — `speakNeural` had grown its own inline
    /// version of `play` and, with it, lost the `tts.áudio` duration line the
    /// other two log. That line is what tells whether synthesis is slower than
    /// speech itself, so losing it on one engine quietly blinded the trace.
    ///
    /// `failure` wraps the decoded error text: only the Odysseus route names
    /// itself, so a dead server stays distinguishable from a dead endpoint.
    ///
    /// The turn can end while `produce` is awaited (barge-in, stop), hence the
    /// cancellation check before any audio is scheduled.
    private func speakBuffered(id: String,
                               failure: @escaping @MainActor (String) -> String = { $0 },
                               _ produce: @escaping @MainActor () async throws -> Data) {
        preparingID = id
        neuralError = nil
        speechTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await produce()
                if Task.isCancelled { self.preparingID = nil; return }
                self.play(data, id: id)
            } catch {
                self.chunkFailed(error, id: id, failure(SettingsUI.msg(error)))
            }
        }
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
            chunkFailed(error, id: id, SettingsUI.msg(error))
        }
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

    /// Configures the session for playback. Failures used to be four `try?`s, so
    /// a session the OS refused to configure produced silent no-audio and nothing
    /// else — while `VoiceInputManager` raises a localized error for the very same
    /// failure on the recording side. It is reported now: `neuralError` is the
    /// channel the voice UI already renders.
    private func activateTTSSession() {
        #if os(iOS)
        let s = AVAudioSession.sharedInstance()
        do {
            if duplexSession {
                try s.setCategory(.playAndRecord, mode: .voiceChat,
                                  options: [.duckOthers, .allowBluetoothA2DP])
                try s.setActive(true)
                applyProximityRoute()
            } else {
                try s.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                try s.setActive(true)
            }
        } catch {
            VoiceLog.log("sessão", "activateTTSSession FALHOU: \(error.localizedDescription)")
            neuralError = L("Áudio indisponível: %@", error.localizedDescription)
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
    /// The single slot every speech job shares: the neural pack download, a
    /// buffered synthesis on any engine, and the streaming path.
    ///
    /// Assigning it does NOT cancel what was there — only `stop()` cancels. So
    /// a `prepareNeural()` download still running when the first utterance
    /// arrives is merely dropped from the slot and keeps going, and
    /// `ensurePocket` has no in-flight dedupe, so both can load the same pack
    /// at once. Wasteful rather than wrong (the second load wins and the
    /// result is the same weights), and left as it was — but it is what the
    /// slot does, not what its name suggests.
    private var speechTask: Task<Void, Never>?
    /// Releases the turn if the stream never delivers a first byte. See
    /// `speakStreaming`.
    private var streamWatchdog: Task<Void, Never>?

    private var neuralVoice: String { UserDefaults.standard.string(forKey: "voice.tts.pocketVoice") ?? "alba" }
    // No server voice/model settings: the Odysseus synth endpoint takes neither.

    override init() { super.init(); synth.delegate = self }

    func isSpeaking(_ id: String) -> Bool { speakingID == id }
    func isPreparing(_ id: String) -> Bool { preparingID == id }

    /// Speak `text` for message `id`, or stop if it's already active (toggle).
    func toggle(_ text: String, id: String) {
        if speakingID == id || preparingID == id { stop(); return }
        stop()
        let clean = SpokenText.strip(text)
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
        let clean = SpokenText.strip(text)
        guard !clean.isEmpty else { return }
        if streamingAllowed && TTSEngine.current.canStream {
            // `speakStreaming` is a queue routine: every one of its callbacks —
            // first audio, finished, interrupted, the watchdog, and the byte loop
            // itself — is guarded by `chunkID == id`. `stop()` above cleared
            // `chunkID`, so without this the first chunk off the socket returns
            // out of the loop and nothing ever clears `preparingID`: the test
            // spun "Sintetizando…" forever with no sound and no error.
            chunkID = id
            chunkClosed = true      // the whole utterance is already here
            speakStreaming(clean, id: id)
        } else { dispatchSpeak(clean, id: id) }
    }

    /// Routes already-stripped text to the configured engine.
    private func dispatchSpeak(_ clean: String, id: String) {
        switch TTSEngine.current {
        case .endpoint: speakEndpoint(clean, id: id)
        case .server:   speakServer(clean, id: id)
        case .neural:   speakNeural(clean, id: id)
        case .native:   speakNative(clean, id: id)
        }
    }

    /// Loads what the server's TTS service reports (for the Settings footer).
    func loadServerInfo() async {
        guard let api else { return }
        serverStats = await api.ttsStats()
    }

    func stop() {
        clearQueue()
        speechTask?.cancel(); speechTask = nil
        streamWatchdog?.cancel(); streamWatchdog = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player?.stop(); player = nil
        speakingID = nil; preparingID = nil
        // Neither hook is cleared here. `player.stop()` above fires no delegate
        // callback, so stopping is precisely the moment the owner still has to
        // decide whether the turn ended — and the owner does nil both, at each
        // of its own transitions. Clearing `onSpeechFailed` here instead left
        // the failure channel dead for the rest of a turn that any other
        // `stop()` caller happened to interrupt.
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
        preparingID = Self.prepareID
        neuralError = nil
        speechTask = Task {
            do { _ = try await ensurePocket(pack); neuralReady = true }
            catch { neuralError = SettingsUI.msg(error) }
            if preparingID == Self.prepareID { preparingID = nil }
        }
    }

    private func speakNeural(_ clean: String, id: String) {
        let lang = LocalizationManager.shared.active
        // No pack for this language: say so once and still speak, natively.
        // Silently swapping engines would look like the neural setting is
        // ignored; refusing to speak at all would be worse.
        //
        // This writes `neuralError` on a path that goes on to SPEAK, which is
        // why nothing may read that string as "TTS failed" — see
        // `onSpeechFailed`.
        guard let pack = Self.pocketPack(for: lang) else {
            neuralError = L("Voz neural indisponível para %@ — usando a voz nativa.", lang.nativeName)
            speakNative(clean, id: id)
            return
        }
        let voice = neuralVoice
        speakBuffered(id: id) {
            let m = try await self.ensurePocket(pack)
            // The pack is only proven usable once it has loaded, so the flag the
            // Settings screen watches is set here rather than up front.
            self.neuralReady = true
            return try await m.synthesize(text: clean, voice: voice)
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
        speakBuffered(id: id, failure: { L("TTS do servidor falhou: %@", $0) }) {
            try await api.synthesizeSpeech(clean)
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
        // The one playback path that never configured the session. `play`,
        // `prepareDuplexSession` and `speakNative` all do — so streamed audio was
        // silenced by the ring switch under the default category, and silent
        // outright after "Testar reconhecimento" left the session on `.record`.
        activateTTSSession()
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
        // A call, or a route change the app did not cause itself, tears the
        // graph down without delivering the completion callbacks the queue is
        // waiting on. That is a failure of this sentence, not the end of it.
        // (The player filters out the route changes this app triggers through
        // `applyProximityRoute`, or lifting the phone to your ear would end the
        // turn — see `PCMStreamPlayer.tearsDownTheGraph`.)
        streamPlayer.onInterrupted = { [weak self] in
            guard let self, self.chunkID == id else { return }
            self.streamWatchdog?.cancel()
            self.speechTask?.cancel()
            self.chunkFailed(Failure.interrupted, id: id, SettingsUI.msg(Failure.interrupted))
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
            self.speechTask?.cancel()
            self.streamPlayer.stop()
            self.chunkFailed(Failure.silent, id: id, SettingsUI.msg(Failure.silent))
        }
        let t0 = Date()
        speechTask = Task { [weak self] in
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
                self.chunkFailed(error, id: id, SettingsUI.msg(error))
            }
        }
    }

    /// The user's own endpoint, buffered. `VoiceEndpoint` failures already carry
    /// the server's response body, so a 401 and a 404 are distinguishable
    /// without a laptop — nothing here needs to add to the message.
    private func speakEndpoint(_ clean: String, id: String) {
        speakBuffered(id: id) { try await VoiceEndpoint.synthesize(clean) }
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
