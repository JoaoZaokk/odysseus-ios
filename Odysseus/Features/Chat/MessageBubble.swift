import SwiftUI
import MarkdownUI

struct MessageBubble: View {
    let message: Message
    var isStreaming: Bool = false
    var attachmentURL: (String) -> URL? = { _ in nil }
    @Environment(\.theme) private var theme
    @ObservedObject private var speech = SpeechManager.shared
    @State private var showThinking = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 36) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if !isUser { header }
                if !message.attachments.isEmpty { attachmentsView }
                if let thinking = message.thinking, !thinking.isEmpty {
                    thinkingBlock(thinking)
                }
                if !message.content.isEmpty || message.attachments.isEmpty { bubble }
            }
            if !isUser { Spacer(minLength: 36) }
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
            Text(message.model?.split(separator: "/").last.map(String.init) ?? "Odysseus")
                .font(.ody(size: 11, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
            if !message.content.isEmpty {
                Button {
                    speech.toggle(message.content, id: message.id)
                } label: {
                    if speech.isPreparing(message.id) {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: speech.isSpeaking(message.id) ? "speaker.wave.2.fill" : "speaker.wave.2")
                            .font(.ody(size: 11))
                            .foregroundStyle(speech.isSpeaking(message.id) ? theme.accent : theme.secondaryText)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        Group {
            if message.content.isEmpty && isStreaming {
                TypingDots()
            } else if isUser {
                Text(message.content)
                    .font(.ody(.body, design: .monospaced))
                    .foregroundStyle(theme.fg)
                    .textSelection(.enabled)
            } else {
                Markdown(message.content)
                    .markdownTextStyle { ForegroundColor(theme.fg) }
                    .markdownTextStyle(\.code) {
                        FontFamilyVariant(.monospaced)
                        BackgroundColor(theme.panel)
                    }
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isUser ? theme.userBubble : theme.aiBubble,
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(theme.border.opacity(0.35), lineWidth: isUser ? 0 : 1)
        )
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    @ViewBuilder
    private func thinkingBlock(_ text: String) -> some View {
        DisclosureGroup(isExpanded: $showThinking) {
            Text(text)
                .font(.ody(size: 12, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Label(LocalizedStringKey(isStreaming ? "Pensando…" : "Raciocínio"), systemImage: "brain")
                .font(.ody(size: 12, design: .monospaced))
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
