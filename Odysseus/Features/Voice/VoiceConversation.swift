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

    @Published private(set) var phase: Phase = .idle
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
    private let speechLevel: Float = 0.04
    private var sttIsNative: Bool {
        let e = UserDefaults.standard.string(forKey: "voice.stt.engine")
        return e != "model" && e != "server"
    }
    private var streamTask: Task<Void, Never>?
    private var speakingTurnID = ""

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
        enableProximity()
        await listen()
    }

    func stop() {
        active = false
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
        guard active else { return }
        reply = ""; liveText = ""; lastPartial = ""
        heardSpeech = false
        guard await voice.start() else { active = false; phase = .idle; return }
        phase = .listening
        lastChange = Date(); lastLoud = Date()
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
        if lvl > speechLevel { heardSpeech = true; lastLoud = Date() }
    }

    private func checkSilence() {
        guard phase == .listening else { return }
        if sttIsNative {
            guard !lastPartial.isEmpty else { return }
            if Date().timeIntervalSince(lastChange) > endpointSilence { endTurn() }
        } else {
            guard heardSpeech else { return }
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
        let replyTurn = Turn(role: "assistant", text: "")
        turns.append(replyTurn)
        speakingTurnID = replyTurn.id
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let sid = try await self.ensureSession(firstMessage: userText)
                let opts = ChatStreamOptions(model: self.selectedModel)
                for try await u in self.stream.send(message: userText, sessionID: sid, options: opts) {
                    if Task.isCancelled { return }
                    switch u {
                    case .textDelta(let d):
                        self.reply += d
                        if let i = self.turns.lastIndex(where: { $0.id == replyTurn.id }) {
                            self.turns[i].text = self.reply
                        }
                    case .error(let m): self.error = m
                    default: break
                    }
                }
                self.speak()
            } catch is CancellationError {
                self.afterSpeaking()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.afterSpeaking()
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

    private func speak() {
        let t = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard active, !t.isEmpty else { afterSpeaking(); return }
        phase = .speaking
        tts.onSpeechFinished = { [weak self] in self?.afterSpeaking() }
        tts.toggle(t, id: speakingTurnID)
        // Listen for the user cutting in while the reply plays.
        let bargeOn = UserDefaults.standard.object(forKey: "voice.bargein.enabled") as? Bool ?? true
        if bargeOn { bargeMonitor.start { [weak self] in self?.bargeIn() } }
    }

    /// User started talking over the reply → stop speaking and listen.
    private func bargeIn() {
        guard phase == .speaking else { return }
        bargeMonitor.stop()
        tts.onSpeechFinished = nil   // transition here; AVAudioPlayer.stop fires no callback
        tts.stop()
        afterSpeaking()
    }

    private func afterSpeaking() {
        bargeMonitor.stop()
        tts.onSpeechFinished = nil
        guard active else { phase = .idle; return }
        Task { await listen() }
    }
}
