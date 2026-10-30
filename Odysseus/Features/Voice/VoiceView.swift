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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .background(GeometryReader { geo in
                        Color.clear
                            .onAppear { height = geo.size.height }
                            .onChange(of: geo.size.height) { _, h in height = h }
                    })
                // With nothing said yet the orb sits a fixed 64 under the
                // header; it used to be pushed ~600 pt down by an empty
                // transcript taking all the height. The button keeps its
                // breathing room above the home indicator.
                VStack(spacing: 0) {
                    if hasTranscript {
                        transcript
                        Spacer(minLength: 8)
                    }
                    orb
                        .padding(.top, hasTranscript ? 8 : Spacing.voidOffset)
                    statusLine
                    Spacer(minLength: 8)
                    controlButton
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.top, 8)
                .padding(.bottom, Spacing.bottomBreathing)
            }
            .navigationTitle(Text("Voz"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A glass circle like every other bar button: on the iPhone
                // Duo the system moves it into the side rail, where a text
                // pill stood out next to the round ones.
                ToolbarItem(placement: .cancellationAction) {
                    Button { convo.stop(); dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.ody(.body, weight: .semibold))
                            .foregroundStyle(theme.fg)
                    }
                    .accessibilityLabel(Text("Fechar"))
                }
                // The model rides under the title, as in the chat. As its own
                // trailing pill it pushed into "Voz" whenever the name was long.
                ToolbarItem(placement: .principal) { titleMenu }
            }
        }
        .tint(theme.accent)
        .presentationDragIndicator(.visible)
        .onChange(of: convo.phase) { _, p in pulse = p.isLive }
        .task {
            await convo.loadModels()
            if TTSEngine.current == .server { await speech.loadServerInfo() }
        }
        .onAppear {
            if let s = seedSession { convo.seed(sessionID: s.id, messages: s.messages) }
            #if DEBUG
            if ScreenshotRoute.voiceAutoStart { Task { await convo.startSession() } }
            #endif
        }
        .onDisappear { convo.stop() }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 620)
        #endif
    }

    private var hasTranscript: Bool { !convo.turns.isEmpty || !convo.liveText.isEmpty }

    /// Height the sheet has to work with. The iPhone Duo's outer display is
    /// 678 pt tall: a 120 pt disc with its rings left the transcript a sliver.
    @State private var height: CGFloat = 800
    private var orbSize: CGFloat { height < 720 ? 92 : 120 }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
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

    static func inlineMarkdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }

    @ViewBuilder
    private func bubble(_ turn: VoiceConversation.Turn) -> some View {
        if let notice = turn.notice {
            noticeCard(notice, text: turn.text)
        } else {
            let isUser = turn.role == "user"
            HStack {
                if isUser { Spacer(minLength: 40) }
                // Inline markdown rendered: replies are written for the chat, and
                // the transcript showed their "**Dia 1:**" raw.
                // A searched reply cites its pages as "[2]" — noise in a spoken
                // conversation, and the transcript has no list to point at.
                // Same shapes as the chat: the user in a bubble, the reply as text.
                Text(Self.inlineMarkdown(turn.text.isEmpty ? "…"
                    : isUser ? turn.text
                    : turn.text.replacingOccurrences(of: "\\s*\\[\\d+(?:\\s*,\\s*\\d+)*\\]",
                                                     with: "", options: .regularExpression)))
                    .font(.ody(.callout))
                    .foregroundStyle(theme.fg)
                    .padding(.horizontal, isUser ? 14 : 0).padding(.vertical, isUser ? 10 : 2)
                    .background(isUser ? theme.userBubble : .clear,
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                if !isUser { Spacer(minLength: 40) }
            }
        }
    }

    /// A reply that never came, said as what happened and what to do — not
    /// as a message from the model.
    private func noticeCard(_ notice: VoiceConversation.Notice, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notice == .webSearchOff ? "globe" : "exclamationmark.triangle")
                .font(.ody(.body))
                .foregroundStyle(theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if notice == .webSearchOff {
                    Text("A busca na web está desligada")
                        .font(.ody(.subheadline, weight: .semibold))
                        .foregroundStyle(theme.fg)
                }
                Text(verbatim: text)
                    .font(.ody(.subheadline))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if notice == .webSearchOff {
                    NavigationLink {
                        VoiceSettingsView()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Voz e modelos")
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }
                        .font(.ody(.subheadline, weight: .semibold))
                        .foregroundStyle(theme.accentText)
                        .frame(minHeight: Spacing.tapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.warning.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Orb

    /// One solid disc and two soft rings that breathe while the conversation
    /// is live. A `Button`: it was a tap gesture on a circle, which VoiceOver
    /// did not announce as anything.
    private var orb: some View {
        Button { convo.tapOrb() } label: {
            ZStack {
                // Only the rings breathe; the glyph and spinner stay still.
                ZStack {
                    Circle()
                        .fill(theme.accent.opacity(0.07))
                        .frame(width: orbSize * 1.5, height: orbSize * 1.5)
                        .scaleEffect(pulse && !reduceMotion ? 1.08 : 1)
                    Circle()
                        .fill(theme.accent.opacity(0.16))
                        .frame(width: orbSize * 1.23, height: orbSize * 1.23)
                        .scaleEffect(pulse && !reduceMotion ? 1.05 : 1)
                }
                .animation(pulse ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                 : .easeOut(duration: 0.3), value: pulse)
                Circle().fill(theme.accentFill).frame(width: orbSize, height: orbSize)
                Group {
                    if convo.phase.isBusy {
                        ProgressView().tint(theme.onAccent).controlSize(.large)
                    } else {
                        Image(systemName: orbIcon).font(.ody(size: orbSize / 3, weight: .semibold))
                            .foregroundStyle(theme.onAccent)
                    }
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(convo.active ? "Encerrar" : "Iniciar conversa")))
        .accessibilityValue(Text(verbatim: statusText))
    }

    private var orbIcon: String {
        if convo.phase.isListening { return "waveform" }
        if convo.phase.isSpeaking  { return "speaker.wave.3.fill" }
        return "mic.fill"
    }

    /// Errors read as errors: they shared this grey line with "Ouvindo…".
    private var statusLine: some View {
        HStack(spacing: 6) {
            if convo.error != nil {
                Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
            }
            Text(statusText)
        }
        .font(.ody(.subheadline))
        .foregroundStyle(convo.error == nil ? theme.secondaryText : theme.danger)
        .padding(.top, 16)
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
        case .thinking where convo.searching: return L("Pesquisando na web") + "…"
        case .transcribing, .thinking, .finishing: return L("Pensando…")
        }
    }

    // MARK: - Controls

    /// Start is the one filled button on the screen; stop is quiet, with the
    /// stop glyph in red, so the two states never look alike.
    private var controlButton: some View {
        Button { convo.toggleSession() } label: {
            HStack(spacing: 8) {
                Image(systemName: convo.active ? "stop.fill" : "mic.fill")
                    .foregroundStyle(convo.active ? theme.danger : theme.onAccent)
                Text(LocalizedStringKey(convo.active ? "Encerrar" : "Iniciar conversa"))
                    .font(.ody(.headline, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(convo.active ? theme.panel : theme.accentFill, in: Capsule())
            .foregroundStyle(convo.active ? theme.fg : theme.onAccent)
            .overlay(Capsule().stroke(convo.active ? theme.fg.opacity(0.12) : .clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// "Voz" over the model in use; when the server lists models, the pair
    /// is the menu that changes it.
    @ViewBuilder private var titleMenu: some View {
        if convo.models.isEmpty {
            Text("Voz")
                .font(.ody(.headline, weight: .semibold))
                .foregroundStyle(theme.fg)
                .accessibilityAddTraits(.isHeader)
        } else {
            Menu {
                Button("Padrão do servidor") { convo.selectedModel = nil }
                Divider()
                ForEach(convo.models.filter { !$0.isExtra }) { m in
                    Button(m.name) { convo.selectedModel = m }
                }
                // Same menu as the chat's model chip.
                let extras = convo.models.filter(\.isExtra)
                if !extras.isEmpty {
                    Menu("Outros modelos") {
                        ForEach(extras) { m in Button(m.name) { convo.selectedModel = m } }
                    }
                }
            } label: {
                VStack(spacing: 1) {
                    Text("Voz")
                        .font(.ody(.headline, weight: .semibold))
                        .foregroundStyle(theme.fg)
                    HStack(spacing: 3) {
                        Text(verbatim: convo.selectedModel?.name ?? L("Padrão do servidor"))
                            .lineLimit(1).truncationMode(.middle)
                        Image(systemName: "chevron.down").accessibilityHidden(true)
                    }
                    .font(.ody(.caption))
                    .foregroundStyle(theme.secondaryText)
                }
                .frame(maxWidth: 220)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Modelo"))
            .accessibilityValue(Text(verbatim: convo.selectedModel?.name ?? L("Padrão do servidor")))
        }
    }
}
