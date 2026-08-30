import SwiftUI

/// Voice-first conversation screen — hands-free "talk to it". Tap the orb (or
/// the button) to start; it then loops listen → think → speak on its own until
/// stopped, and speaking over the reply cuts it short (barge-in).
///
/// Opened from the chat's voice button. The conversation is a normal server
/// session, so it keeps showing up in Conversas afterwards.
struct VoiceView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var convo: VoiceConversation
    @ObservedObject private var speech = SpeechManager.shared
    @State private var pulse = false
    private let seedSession: (id: String, messages: [Message])?

    init(app: AppState, session: String? = nil, messages: [Message] = [],
         onSessionCreated: ((String) -> Void)? = nil) {
        let vm = VoiceConversation(api: app.api, stream: app.stream)
        vm.onSessionCreated = onSessionCreated
        _convo = StateObject(wrappedValue: vm)
        seedSession = session.map { ($0, messages) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    transcript
                    Spacer(minLength: 8)
                    orb
                    statusLine
                    Spacer(minLength: 8)
                    controlButton
                }
                .padding(16)
            }
            .navigationTitle("Voz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { convo.stop(); dismiss() }
                }
                ToolbarItem(placement: .primaryAction) { modelPicker }
            }
        }
        .tint(theme.accent)
        .onChange(of: convo.phase) { _, p in pulse = p.isLive }
        .task {
            await convo.loadModels()
            if TTSEngine.current == .server { await speech.loadServerInfo() }
        }
        .onAppear {
            if let s = seedSession { convo.seed(sessionID: s.id, messages: s.messages) }
        }
        .onDisappear { convo.stop() }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 620)
        #endif
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(convo.turns) { turn in bubble(turn).id(turn.id) }
                    if !convo.liveText.isEmpty {
                        bubble(.init(role: "user", text: convo.liveText)).opacity(0.6)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .onChange(of: convo.turns.count) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
            .onChange(of: convo.reply) { _, _ in proxy.scrollTo("bottom") }
        }
    }

    private func bubble(_ turn: VoiceConversation.Turn) -> some View {
        let isUser = turn.role == "user"
        return HStack {
            if isUser { Spacer(minLength: 40) }
            Text(turn.text.isEmpty ? "…" : turn.text)
                .font(.ody(.subheadline))
                .foregroundStyle(theme.fg)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(isUser ? theme.userBubble : theme.aiBubble,
                            in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.border, lineWidth: 1))
            if !isUser { Spacer(minLength: 40) }
        }
    }

    // MARK: - Orb

    private var orb: some View {
        ZStack {
            Circle()
                .fill(theme.accent.opacity(0.18))
                .frame(width: 190, height: 190)
                .scaleEffect(pulse ? 1.12 : 0.9)
                .animation(pulse ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                 : .easeOut(duration: 0.3), value: pulse)
            Circle().fill(theme.accent.opacity(0.30)).frame(width: 140, height: 140)
            Circle().fill(theme.accent).frame(width: 104, height: 104)
            Group {
                if convo.phase.isBusy {
                    ProgressView().tint(theme.bg).controlSize(.large)
                } else {
                    Image(systemName: orbIcon).font(.ody(size: 40, weight: .semibold))
                        .foregroundStyle(theme.bg)
                }
            }
        }
        .contentShape(Circle())
        .onTapGesture { convo.tapOrb() }
    }

    private var orbIcon: String {
        if convo.phase.isListening { return "waveform" }
        if convo.phase.isSpeaking  { return "speaker.wave.3.fill" }
        return "mic.fill"
    }

    private var statusLine: some View {
        Text(statusText)
            .font(.ody(.subheadline))
            .foregroundStyle(theme.secondaryText)
            .padding(.top, 14)
            .multilineTextAlignment(.center)
    }

    private var statusText: String {
        if let e = convo.error { return e }
        // Switched rather than asked, so a new phase has to be given a line
        // here instead of falling into a default that says the wrong thing.
        switch convo.phase {
        case .idle:      return convo.active ? "…" : L("Toque para conversar")
        case .listening: return L("Ouvindo…")
        case .speaking:  return L("Falando…")
        // Finalizing the recording and handing the turn back are the same thing
        // to the person waiting: working, nothing to hear yet. They share the
        // one string that already says that.
        case .transcribing, .thinking, .finishing: return L("Pensando…")
        }
    }

    // MARK: - Controls

    private var controlButton: some View {
        Button { convo.toggleSession() } label: {
            HStack(spacing: 8) {
                Image(systemName: convo.active ? "stop.fill" : "mic.fill")
                Text(LocalizedStringKey(convo.active ? "Encerrar" : "Iniciar conversa"))
                    .font(.ody(.headline))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(convo.active ? theme.panel : theme.accent,
                        in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(convo.active ? theme.accent : Color.white)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(convo.active ? theme.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var modelPicker: some View {
        if !convo.models.isEmpty {
            Menu {
                Button("Padrão do servidor") { convo.selectedModel = nil }
                ForEach(convo.models.filter { !$0.isExtra }) { m in
                    Button(m.name) { convo.selectedModel = m }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(convo.selectedModel?.name ?? L("Modelo"))
                        .font(.ody(size: 11)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.ody(size: 8))
                }
                .foregroundStyle(theme.accent).frame(maxWidth: 140, alignment: .trailing)
            }
        }
    }
}
