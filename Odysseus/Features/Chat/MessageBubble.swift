import SwiftUI
import MarkdownUI

struct MessageBubble: View, Equatable {
    let message: Message
    var isStreaming: Bool = false
    var attachmentURL: (String) -> URL? = { _ in nil }

    /// Only what changes the drawing. With `.equatable()` in the transcript a
    /// token redraws the streaming bubble, not every bubble of a long chat. The
    /// closure is the view model's and never changes; speech, visibility and
    /// the blur toggle still invalidate on their own.
    static func == (a: MessageBubble, b: MessageBubble) -> Bool {
        a.message == b.message && a.isStreaming == b.isStreaming
    }
    @Environment(\.theme) private var theme
    @ObservedObject private var speech = SpeechManager.shared
    @State private var showThinking = false
    /// Off by default, like the web's censor. Assistant text only, never
    /// while streaming; a tap reveals until the next hide.
    @AppStorage("chat.sensitiveBlur") private var sensitiveBlur = false
    @State private var revealed = false
    /// The reply's body size, following Dynamic Type: MarkdownUI draws at a
    /// fixed size from its own font properties and ignores `.font`.
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17
    @State private var selecting = false
    /// Settings › Aparência › Personalizar interface.
    @AppStorage(UIVisibility.storageKey) private var uiRaw = ""
    private var ui: UIVisibility { UIVisibility(raw: uiRaw) }

    private var isUser: Bool { message.role == .user }
    private var blurred: Bool {
        sensitiveBlur && !revealed && !isUser && !isStreaming && SensitiveRedactor.hasSensitive(message.content)
    }

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 36) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if !isUser { header }
                if !message.attachments.isEmpty { attachmentsView }
                if ui.isOn(.thinking), let thinking = message.thinking, !thinking.isEmpty {
                    thinkingBlock(thinking)
                }
                if !message.content.isEmpty || message.attachments.isEmpty { bubble }
                // What you sent can be heard too — the 🔊 used to live only in
                // the assistant's header, so a sent message had no way to play.
                if isUser && !message.content.isEmpty && !isStreaming { speakerButton }
                if let n = speech.notice(for: message.id) {
                    Text(verbatim: n)
                        .font(.ody(size: 10))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 280, alignment: isUser ? .trailing : .leading)
                }
            }
            if !isUser { Spacer(minLength: 0) }
        }
    }

    private var attachmentsView: some View {
        let cols = [GridItem(.adaptive(minimum: 90, maximum: 140), spacing: 6)]
        return LazyVGrid(columns: cols, alignment: isUser ? .trailing : .leading, spacing: 6) {
            ForEach(message.attachments, id: \.self) { id in
                AsyncImage(url: attachmentURL(id)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                    case .failure: ZStack { theme.panel; Image(systemName: "photo").foregroundStyle(theme.secondaryText) }
                    default: ZStack { theme.panel; ProgressView().controlSize(.small) }
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border.opacity(0.4), lineWidth: 1))
            }
        }
        .frame(maxWidth: 280, alignment: isUser ? .trailing : .leading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            BrandMark(size: 16)
            // The web's chat-meta: the name can go, the speaker stays.
            if ui.isOn(.modelName) {
                Text(message.model?.split(separator: "/").last.map(String.init) ?? "Odysseus")
                    .font(.ody(.footnote))
                    .foregroundStyle(theme.secondaryText)
            }
            if !message.content.isEmpty { speakerButton }
        }
    }

    /// Read this message aloud, or stop. The glyph stays 11 pt but the target
    /// is not: an 11 pt icon alone was a hit area most taps missed.
    private var speakerButton: some View {
        let speaking = speech.isSpeaking(message.id)
        return Button {
            speech.toggle(message.content, id: message.id)
        } label: {
            Group {
                if speech.isPreparing(message.id) {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: speaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                        .font(.ody(.footnote))
                        .foregroundStyle(speaking ? theme.accent : theme.secondaryText)
                }
            }
            .frame(width: Spacing.tapTarget, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(speaking ? L("Parar leitura") : L("Ouvir mensagem")))
    }

    @ViewBuilder
    private var bubble: some View {
        Group {
            if message.content.isEmpty && isStreaming {
                TypingDots()
            } else if isUser {
                Text(message.content)
                    .font(.ody(.body))
                    .foregroundStyle(theme.fg)
                    .textSelection(.enabled)
            } else {
                // In the app's font: it came out in SF 16 whatever was picked
                // in Aparência, next to titles and lists in another family.
                Markdown(ReplyMarkup.clean(message.content))
                    // One line per newline, as on the web: options a model writes
                    // one per line were joined into a single paragraph.
                    .markdownSoftBreakMode(.lineBreak)
                    .markdownTextStyle {
                        FontFamily(Self.markdownFamily)
                        FontSize(bodySize)
                        ForegroundColor(theme.fg)
                    }
                    .markdownTextStyle(\.code) {
                        // A family, not the variant: Inter has no monospaced
                        // face, so `.monospaced()` on it stayed proportional.
                        FontFamily(.system(.monospaced))
                        FontSize(.em(0.88))
                        BackgroundColor(theme.panel)
                    }
                    // Mermaid, SVG and HTML drawn as on the web; other code with
                    // its language and a copy button (RichBlocks.swift).
                    .markdownBlockStyle(\.codeBlock) { CodeBlockView(configuration: $0) }
                    .textSelection(.enabled)
            }
        }
        .blur(radius: blurred ? 7 : 0)
        .overlay {
            if blurred {
                Button { revealed = true } label: {
                    Label("Conteúdo sensível — toque para mostrar", systemImage: "eye.slash")
                        .font(.ody(size: 11)).foregroundStyle(theme.fg)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(theme.panel, in: Capsule())
                }
                .buttonStyle(.plain)
            } else if sensitiveBlur && revealed && !isUser {
                VStack { Spacer(); HStack { Spacer()
                    Button { revealed = false } label: { Image(systemName: "eye.slash").font(.ody(size: 10)).foregroundStyle(theme.secondaryText) }
                        .buttonStyle(.plain).padding(6)
                } }
            }
        }
        // The user's words in a bubble; the reply as the page itself, full
        // width, the way long answers read best. Boxing both made every
        // screen a stack of cards.
        .padding(.horizontal, isUser ? 14 : 0)
        .padding(.vertical, isUser ? 10 : 0)
        .background(isUser ? theme.userBubble : .clear,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        #if os(iOS)
        // `.textSelection` on iPhone copies the whole bubble or nothing; a part
        // of an answer is selected in a text view (ported from Open WebUI 1.12).
        .contextMenu {
            if !message.content.isEmpty && !isStreaming && !blurred {
                Button { Clipboard.copy(message.content) } label: {
                    Label("Copiar", systemImage: "doc.on.doc")
                }
                Button { selecting = true } label: {
                    Label("Selecionar texto", systemImage: "selection.pin.in.out")
                }
            }
        }
        .sheet(isPresented: $selecting) { SelectableTextSheet(text: message.content) }
        #endif
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private static var markdownFamily: FontProperties.Family {
        if let name = Appearance.fontFamily.customName { return .custom(name) }
        return .system(Appearance.fontFamily.design)
    }

    @ViewBuilder
    private func thinkingBlock(_ text: String) -> some View {
        DisclosureGroup(isExpanded: $showThinking) {
            Text(text)
                .font(.ody(size: 12))
                .foregroundStyle(theme.secondaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Label(LocalizedStringKey(isStreaming ? "Pensando…" : "Raciocínio"), systemImage: "brain")
                .font(.ody(size: 12))
                .foregroundStyle(theme.secondaryText)
        }
        .tint(theme.secondaryText)
        .padding(10)
        .background(theme.panel.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Three-dot pulsing indicator while waiting for the first token.
struct TypingDots: View {
    @Environment(\.theme) private var theme
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(theme.fg.opacity(0.7))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == Double(i) ? 1.0 : 0.5)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever()) { phase = 2 }
        }
        .frame(height: 14)
    }
}
