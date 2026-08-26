import Foundation
import Combine
#if os(iOS)
import UIKit
#endif

/// Hands-free voice conversation: **listen → think → speak → listen**, looping
/// until stopped. It glues the existing STT (`VoiceInputManager`) and TTS
/// (`SpeechManager`) engines to a streamed reply.
///
/// Unlike the Open WebUI version this was ported from, there is no local
/// transcript to push back: `/api/chat_stream` runs against a server-side
/// session that already persists every turn, so the conversation shows up in
/// Conversas on its own. For the same reason no voice-specific system prompt is
/// injected — the session's own prompt is the server's to decide. Replies can
/// therefore arrive with markdown, which `SpeechManager.strip` removes before
/// speaking.
@MainActor
final class VoiceConversation: ObservableObject {
    enum Phase: Equatable { case idle, listening, thinking, speaking }

    @Published private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { VoiceLog.log("phase", "\(oldValue) → \(phase)") } }
    }
    @Published private(set) var active = false
    @Published var turns: [Turn] = []
    @Published var liveText = ""        // partial user transcription while listening
    @Published var reply = ""           // streaming assistant reply
    @Published var error: String?
    @Published var selectedModel: ChatModel?
    @Published private(set) var models: [ChatModel] = []

    struct Turn: Identifiable, Equatable {
        var id: String = UUID().uuidString
        let role: String
        var text: String
        var at = Date()
    }

    private let api: APIClient
    private let stream: ChatStreamClient
    private let voice = VoiceInputManager()
    private let tts = SpeechManager.shared
    private let bargeMonitor = BargeInMonitor()

    /// Server session this voice conversation writes to (created on first turn).
    private(set) var sessionID: String?
    /// Fired when a brand-new session is materialized, so the sidebar refreshes.
    var onSessionCreated: ((String) -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private var silenceTimer: Timer?
    private var lastPartial = ""
    private var lastChange = Date()
    // Energy-based endpointing, for engines with no live transcript.
    private var heardSpeech = false
    private var lastLoud = Date()
    private var turnStarted = Date()
    private var loudestHeard: Float = 0
    private let speechLevel: Float = 0.04
    /// A turn where nothing ever crossed the gate ends anyway. It used to sit
    /// there indefinitely with the mic open, and the orb was the only way out.
    private let maxSilentTurn: TimeInterval = 12

    /// Gate for "the user is talking", for the engines with no live transcript.
    /// Anchored to the loudest thing heard this turn and capped at the old flat
    /// value, so it can only ever be *more* sensitive than 0.04 was, never less:
    /// a soft voice in a quiet room never reached the flat threshold, and the
    /// turn then never ended on its own.
    private var speechGate: Float {
        max(0.015, min(speechLevel, loudestHeard * 0.35))
    }
    private var sttIsNative: Bool {
        let e = UserDefaults.standard.string(forKey: "voice.stt.engine")
        return e != "model" && e != "server" && e != "endpoint"
    }
    private var streamTask: Task<Void, Never>?
    private var speakingTurnID = ""
    /// False until this reply has queued its first chunk — see `openingCut`.
    private var openedThisTurn = false
    /// Set while a turn is being handed back to `listen()`, cleared once the
    /// recorder is actually up. Stops two finalizers from queueing two
    /// `listen()` calls; see `afterSpeaking()`.
    private var finishing = false
    /// Reply text received but not yet handed to TTS. Complete sentences are cut
    /// off the front as they arrive, so speaking starts on the first one instead
    /// of after the whole generation.
    private var pendingSpeech = ""

    /// How long the transcription must stay unchanged before the turn counts as
    /// finished. Only the native engine has live partials; the others fall back
    /// to loudness, and the user can always tap the orb to end the turn.
    private let endpointSilence: TimeInterval = 1.6

    init(api: APIClient, stream: ChatStreamClient) {
        self.api = api
        self.stream = stream
        voice.api = api   // enables the "server" STT engine
        voice.$partialText
            .receive(on: RunLoop.main)
            .sink { [weak self] t in self?.partialChanged(t) }
            .store(in: &cancellables)
        voice.$level
            .receive(on: RunLoop.main)
            .sink { [weak self] lvl in self?.levelChanged(lvl) }
            .store(in: &cancellables)
        voice.$error
            .receive(on: RunLoop.main)
            .sink { [weak self] e in if let e { self?.error = e } }
            .store(in: &cancellables)
        // Recover the loop if TTS fails to produce audio — without this the
        // conversation would sit in .speaking forever and never listen again.
        tts.$neuralError
            .receive(on: RunLoop.main)
            .sink { [weak self] e in
                guard let self, let e, self.phase == .speaking else { return }
                self.error = e
                self.afterSpeaking()
            }
            .store(in: &cancellables)
    }

    func loadModels() async {
        guard models.isEmpty else { return }
        models = (try? await api.models()) ?? []
    }

    // MARK: - Session control

    func toggleSession() {
        if active { stop() } else { Task { await startSession() } }
    }

    /// Continues an existing conversation by voice (opened from a chat).
    func seed(sessionID id: String, messages: [Message]) {
        guard sessionID == nil else { return }
        sessionID = id
        turns = messages.map {
            Turn(role: $0.role == .user ? "user" : "assistant", text: $0.content)
        }
    }

    /// Clears everything for a brand-new conversation.
    func reset() {
        stop()
        turns = []; reply = ""; liveText = ""; error = nil
        sessionID = nil
    }

    func startSession() async {
        guard !active else { return }
        active = true; error = nil; reply = ""
        tts.duplexSession = true   // play-AND-record so barge-in can listen mid-reply
        // Warm the VAD model here: loading it on the first reply would stall the
        // moment the user is waiting on.
        Task { await BargeInMonitor.prepare() }
        enableProximity()
        await listen()
    }

    func stop() {
        active = false
        finishing = false
        streamTask?.cancel(); streamTask = nil
        silenceTimer?.invalidate(); silenceTimer = nil
        bargeMonitor.stop()
        tts.onSpeechFinished = nil
        tts.duplexSession = false
        tts.stop()
        voice.cancel()
        disableProximity()
        phase = .idle
        liveText = ""
    }

    // MARK: - Proximity (to the ear → earpiece, else loudspeaker)

    private func enableProximity() {
        #if os(iOS)
        UIDevice.current.isProximityMonitoringEnabled = true
        NotificationCenter.default
            .publisher(for: UIDevice.proximityStateDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.tts.applyProximityRoute() }
            .store(in: &cancellables)
        #endif
    }

    private func disableProximity() {
        #if os(iOS)
        UIDevice.current.isProximityMonitoringEnabled = false
        #endif
    }

    /// Tap the orb mid-turn: end listening early, or skip the spoken reply.
    func tapOrb() {
        switch phase {
        case .listening: endTurn()
        case .speaking:  bargeIn()
        case .thinking, .idle: break
        }
    }

    // MARK: - Listen (STT)

    private func listen() async {
        // Every exit from here must release the handoff latch, including this
        // one. Leaving it set would park the loop exactly the way the old
        // phase-based guard in afterSpeaking() did.
        guard active else { finishing = false; return }
        // Cleared per turn: a single failure used to replace "Ouvindo…" for the
        // rest of the session, hiding whether the loop was still alive.
        error = nil
        reply = ""; liveText = ""; lastPartial = ""
        heardSpeech = false
        loudestHeard = 0
        // Release a recorder left running by an interrupted turn. Without this a
        // single stuck engine made every later start() fail, so neither the orb
        // nor "Start conversation" could revive the screen.
        voice.cancel()
        guard await voice.start() else {
            VoiceLog.log("listen", "voice.start() FALHOU — encerrando sessão")
            active = false; phase = .idle; finishing = false; return
        }
        VoiceLog.log("listen", "gravando (nativo=\(sttIsNative))")
        phase = .listening
        finishing = false            // the turn handoff is complete
        lastChange = Date(); lastLoud = Date(); turnStarted = Date()
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkSilence() }
        }
    }

    private func partialChanged(_ t: String) {
        guard phase == .listening else { return }
        liveText = t
        if t != lastPartial { lastPartial = t; lastChange = Date() }
    }

    private func levelChanged(_ lvl: Float) {
        guard phase == .listening else { return }
        loudestHeard = max(loudestHeard, lvl)
        if lvl > speechGate { heardSpeech = true; lastLoud = Date() }
    }

    private func checkSilence() {
        guard phase == .listening else { return }
        if sttIsNative {
            guard !lastPartial.isEmpty else { return }
            if Date().timeIntervalSince(lastChange) > endpointSilence { endTurn() }
        } else {
            guard heardSpeech else {
                // Nothing ever crossed the gate — a mic that is muted, routed
                // elsewhere, or simply a room quieter than the gate. End it
                // rather than hold the mic open forever: endTurn() transcribes
                // what there is, and an empty result just goes back to
                // listening.
                if Date().timeIntervalSince(turnStarted) > maxSilentTurn {
                    VoiceLog.log("stt.fim", "nada acima do piso em \(Int(maxSilentTurn))s — encerrando turno")
                    endTurn()
                }
                return
            }
            if Date().timeIntervalSince(lastLoud) > endpointSilence { endTurn() }
        }
    }

    private func endTurn() {
        guard phase == .listening else { return }
        silenceTimer?.invalidate(); silenceTimer = nil
        phase = .thinking          // freezes the silence watcher; stop() finalizes STT
        Task {
            let text = await voice.stop()
            guard active else { return }
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            VoiceLog.log("stt", t.isEmpty ? "vazio — voltando a escutar" : "\(t.count) chars: \"\(t.prefix(60))\"")
            guard !t.isEmpty else { await listen(); return }   // heard nothing → keep listening
            turns.append(Turn(role: "user", text: t))
            liveText = ""
            ask(t)
        }
    }

    // MARK: - Think (the model)

    private func ask(_ userText: String) {
        phase = .thinking
        reply = ""
        pendingSpeech = ""
        openedThisTurn = false
        let replyTurn = Turn(role: "assistant", text: "")
        turns.append(replyTurn)
        speakingTurnID = replyTurn.id
        streamTask = Task { [weak self] in
            guard let self else { return }
            // Timed because the voice loop's wait is *not* obviously the TTS:
            // the first device log showed 12–27 s between the transcript and
            // the first spoken sentence, against ~0.5 s of synthesis. Without
            // these two marks there is no way to tell a slow model from a slow
            // session call from a slow endpoint.
            let t0 = Date()
            var firstDelta = true
            do {
                let sid = try await self.ensureSession(firstMessage: userText)
                VoiceLog.log("llm.sessão", String(format: "%.0f ms", Date().timeIntervalSince(t0) * 1000))
                let opts = ChatStreamOptions(model: self.selectedModel)
                for try await u in self.stream.send(message: userText, sessionID: sid, options: opts) {
                    if Task.isCancelled { return }
                    switch u {
                    case .textDelta(let d):
                        if firstDelta {
                            firstDelta = false
                            VoiceLog.log("llm.1ºdelta", String(format: "%.0f ms", Date().timeIntervalSince(t0) * 1000))
                        }
                        self.reply += d
                        if let i = self.turns.lastIndex(where: { $0.id == replyTurn.id }) {
                            self.turns[i].text = self.reply
                        }
                        self.pendingSpeech += d
                        self.emitSentences()
                    case .error(let m): self.error = m
                    default: break
                    }
                }
                // A cancelled stream ends the loop *normally*: the producer
                // turns CancellationError into `continuation.finish()`
                // (ChatStreamClient), so `for try await` returns instead of
                // throwing, and the `if Task.isCancelled` inside the loop never
                // runs again because no further element arrives. Without this
                // check a barge-in still flushed the half-written sentence and
                // spoke it over the user who had just interrupted.
                if Task.isCancelled { return }
                self.emitSentences(flush: true)
                self.finalizeReply(replyTurn.id)
            } catch is CancellationError {
                self.afterSpeaking()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                // Same finalization as a clean end. Calling afterSpeaking()
                // directly here jumped straight back to listening while queued
                // sentences were still playing, so the assistant talked into
                // the open microphone of the next turn.
                self.finalizeReply(replyTurn.id)
            }
        }
    }

    /// Materializes the server session on the first spoken turn, named after it
    /// so the conversation is recognizable in the sidebar.
    private func ensureSession(firstMessage: String) async throws -> String {
        if let sessionID { return sessionID }
        let dc: DefaultChat
        if let m = selectedModel, let url = m.endpointURL, !url.isEmpty {
            dc = DefaultChat(endpointURL: url, model: m.id, endpointID: m.endpointId)
        } else {
            dc = try await api.defaultChat()
        }
        let id = try await api.createSession(from: dc, name: String(firstMessage.prefix(40)))
        sessionID = id
        onSessionCreated?(id)
        return id
    }

    // MARK: - Speak (TTS)

    /// Cuts every complete sentence off `pendingSpeech` and queues it. With
    /// `flush`, whatever is left goes too — the model's last sentence often has
    /// no trailing space to detect.
    ///
    /// The first chunk of a reply is cut by a looser rule (`openingCut`), for
    /// the reason spelled out there.
    private func emitSentences(flush: Bool = false) {
        guard active else { return }
        while let cut = openedThisTurn ? Self.sentenceCut(in: pendingSpeech)
                                       : Self.openingCut(in: pendingSpeech) {
            let sentence = String(pendingSpeech.prefix(cut))
            pendingSpeech.removeFirst(cut)
            queueSpeech(sentence)
        }
        if flush {
            let rest = pendingSpeech
            pendingSpeech = ""
            queueSpeech(rest)
        }
    }

    /// Offset just past the first sentence terminator that is followed by
    /// whitespace. Requiring the space keeps "3.5" and "R$ 1.200,00" intact.
    nonisolated static func sentenceCut(in s: String) -> Int? {
        let chars = Array(s)
        guard chars.count >= 2 else { return nil }
        let terms: Set<Character> = [".", "!", "?", "\n", "。", "！", "？", "…"]
        for i in 0..<(chars.count - 1) where terms.contains(chars[i]) {
            // A newline can't be a decimal separator, so it ends a sentence on
            // its own. Requiring whitespace after it too — as the other
            // terminators do — meant a single line break never cut, and "\n"
            // was effectively dead in the set above.
            if chars[i].isNewline || chars[i + 1].isWhitespace { return i + 1 }
        }
        return nil
    }

    /// Where to cut the **first** chunk of a reply.
    ///
    /// Every later sentence is synthesized while the previous one is still
    /// playing, so its round trip is invisible and it can afford to wait for a
    /// real sentence boundary. The first one has nothing to hide behind: it
    /// costs a whole round trip of silence, and a long opening sentence pays
    /// that round trip *plus* the synthesis of every word in it. So the opening
    /// may also break at a clause boundary once it is long enough not to sound
    /// clipped, and is forced out near `openingHard`.
    ///
    /// The cost is prosody: the engine synthesizes each chunk on its own, so a
    /// clause cut can land a falling intonation mid-sentence. That is the
    /// trade being made deliberately — in a hands-free loop the wait before the
    /// first word is what the user actually notices.
    static let openingSoft = 60
    static let openingHard = 140

    nonisolated static func openingCut(in s: String) -> Int? {
        if let end = sentenceCut(in: s) { return end }
        let chars = Array(s)
        guard chars.count > openingSoft else { return nil }
        let clause: Set<Character> = [",", ";", ":", "—", "–", "，", "；", "：", "、"]
        // The LAST clause break inside the budget, not the first: cutting at the
        // first comma would open the reply with two or three words.
        var best: Int?
        for i in 0..<(chars.count - 1) where clause.contains(chars[i]) {
            let cut = i + 1
            if cut >= openingSoft, cut <= openingHard, chars[cut].isWhitespace { best = cut }
        }
        if let best { return best }
        // No clause break in range — only then split on a space, and only once
        // the text is past the hard limit, so a short opening is never chopped.
        guard chars.count > openingHard else { return nil }
        for i in stride(from: openingHard, through: openingSoft, by: -1) where chars[i].isWhitespace {
            return i
        }
        return nil
    }

    private func queueSpeech(_ sentence: String) {
        let t = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only a turn that is still thinking (first sentence) or speaking may
        // queue audio. Once it has been finalized — barge-in, TTS failure,
        // stream error — a late sentence from the still-live stream would
        // otherwise re-enter .speaking on top of a live recording, swapping the
        // audio-session category out from under the recorder.
        guard active, !finishing, !t.isEmpty,
              phase == .thinking || phase == .speaking else { return }
        // Ask before committing: `enqueue` silently drops a sentence that is
        // pure markdown, and entering .speaking for one left the turn with an
        // empty queue that `closeQueue` could never finish.
        guard SpeechManager.isSpeakable(t) else { return }
        VoiceLog.log("tts.frase", "\(openedThisTurn ? "" : "ABERTURA ")\(t.count) chars: \"\(t.prefix(50))\"")
        openedThisTurn = true
        beginSpeaking()
        tts.enqueue(t, id: speakingTurnID)
    }

    /// Hands the reply over: if audio is playing, let the queue drain and end
    /// the turn from the finish callback; otherwise end it now. Used by both the
    /// clean end of the stream and the error path, so a mid-reply failure can't
    /// jump back to listening while sentences are still being spoken.
    private func finalizeReply(_ id: String) {
        if phase == .speaking {
            tts.closeQueue(id: id)
        } else {
            afterSpeaking()      // nothing was ever spoken — empty or failed reply
        }
    }

    /// Enters the speaking phase on the first sentence. Barge-in is armed here
    /// rather than earlier so the monitor's noise floor settles against audio
    /// that is about to exist.
    private func beginSpeaking() {
        guard phase != .speaking else { return }
        phase = .speaking
        tts.onSpeechFinished = { [weak self] in self?.afterSpeaking() }
        // The recorder leaves the session in .record/.measurement — a mode that
        // disables system signal processing, i.e. the echo cancellation the
        // monitor depends on. Switch to .playAndRecord/.voiceChat first, or the
        // monitor hears the assistant and interrupts it.
        tts.prepareDuplexSession()
        armBargeIn()
    }

    private func armBargeIn() {
        let on = UserDefaults.standard.object(forKey: "voice.bargein.enabled") as? Bool ?? true
        guard on else { return }
        // Without working echo cancellation the monitor hears the assistant's own
        // voice through the speaker and cuts it off mid-sentence, every time. No
        // barge-in is far better than that, so a failed AEC simply doesn't arm.
        // The reason is reported as-is; a model that is merely still loading
        // says nothing, because the next sentence will arm normally.
        if let why = bargeMonitor.start(onSpeech: { [weak self] in self?.bargeIn() }),
           let message = why.message {
            error = message
        }
    }

    /// User started talking over the assistant → drop whatever it was doing and
    /// listen. Valid both while a reply is being written and while it plays.
    private func bargeIn() {
        switch phase {
        case .speaking:
            VoiceLog.log("barge.corta", "reply=\(reply.count) chars — cancelando stream e fala")
            bargeMonitor.stop()
            // The reply is usually still streaming: stopping only the audio left
            // the model writing into `reply`, which listen() had just cleared —
            // so the bubble lost its beginning and the queue kept being fed new
            // sentences to speak after the interruption.
            streamTask?.cancel(); streamTask = nil
            // Cancelling alone isn't enough: the stream's tail still runs (see
            // ask()). Dropping the buffered fragment here means that even if
            // something else flushes it, there is nothing left to speak.
            pendingSpeech = ""
            tts.onSpeechFinished = nil   // transition here; AVAudioPlayer.stop fires no callback
            tts.stop()
            afterSpeaking()
        case .idle, .listening, .thinking:
            // Not armed outside .speaking. Cancelling a streaming reply from
            // here raced the stream's own completion — the loop ends normally
            // on cancellation rather than throwing, so speak() ran anyway and
            // two listen() calls collided, wedging the session with a live mic.
            break
        }
    }

    /// Ends the current turn and goes back to listening.
    ///
    /// Several things can report the turn is over at once — the TTS finish
    /// callback, a barge-in, the neuralError sink, and `ask()`'s own tail — and
    /// two of them arriving used to queue two `listen()` calls. The second found
    /// the recorder already running, `voice.start()` returned false, and the
    /// session was killed with the audio engine still live.
    ///
    /// The gate for that is `finishing`, not the phase. Gating on
    /// `phase == .speaking` looks equivalent but isn't: a reply that never
    /// produces a speakable sentence (empty completion, tool-only turn, stream
    /// error before the first delta) is finalized by `ask()` from `.thinking`,
    /// and that guard swallowed the call, parking the loop in "Pensando…" with
    /// no way back except restarting the session.
    private func afterSpeaking() {
        guard phase == .speaking || phase == .thinking else {
            VoiceLog.log("afterSpeaking", "ignorado, fase=\(phase)")
            return
        }
        guard !finishing else {
            VoiceLog.log("afterSpeaking", "ignorado, turno já finalizando")
            return
        }
        finishing = true
        phase = .thinking            // transitional: not speaking, not yet listening
        bargeMonitor.stop()
        tts.onSpeechFinished = nil
        guard active else { finishing = false; phase = .idle; return }
        Task { await listen() }
    }
}
