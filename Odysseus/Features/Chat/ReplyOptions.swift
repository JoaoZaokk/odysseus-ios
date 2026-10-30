import SwiftUI

/// Options a model wrote out as a question to answer — one per line, each
/// with a radio or checkbox mark. GPT and Claude ask with real buttons (a tool
/// of their platform); a model behind Odysseus has none in chat mode, so it
/// writes them as text. The last group in a reply is offered as buttons.
/// (A formal question from the agent is `AskUserCard`, not this.) Ported from
/// the Open WebUI app 1.12.
enum ReplyOptions {
    private static let radios = ["🔘", "⚪️", "⚪", "◯", "○", "◻️", "🔲", "▫️"]
    private static let boxes = ["- [ ]", "* [ ]", "[ ]", "☐"]

    static func parse(_ text: String) -> [String] {
        var groups: [[String]] = []
        var current: [String] = []
        var inFence = false
        var lastNonOption = ""
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence { continue }
            if line.isEmpty { continue }
            if let option = option(in: line, after: lastNonOption, inGroup: !current.isEmpty) {
                current.append(option)
            } else {
                if current.count >= 2 { groups.append(current) }
                current = []
                lastNonOption = line
            }
        }
        if current.count >= 2 { groups.append(current) }
        return groups.last ?? []
    }

    /// A radio mark is a choice on its own; a checkbox only under a question
    /// (otherwise it is a to-do list).
    private static func option(in line: String, after previous: String, inGroup: Bool) -> String? {
        if let mark = radios.first(where: { line.hasPrefix($0) }) {
            return clean(String(line.dropFirst(mark.count)))
        }
        if let mark = boxes.first(where: { line.hasPrefix($0) }),
           inGroup || plain(previous).hasSuffix("?") {
            return clean(String(line.dropFirst(mark.count)))
        }
        return nil
    }

    private static func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func clean(_ s: String) -> String {
        let t = plain(s).replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
        return t.count > 140 ? String(t.prefix(139)) + "…" : t
    }
}

/// The options under the last reply, as buttons; a tap sends one.
struct ReplyOptionsList: View {
    let options: [String]
    let onPick: (String) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Responder")
                .font(.ody(size: 12))
                .foregroundStyle(theme.secondaryText)
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button { onPick(option) } label: {
                    Text(verbatim: option)
                        .font(.ody(.subheadline))
                        .foregroundStyle(theme.fg)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(theme.aiBubble, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.accent.opacity(0.55), lineWidth: 1))
                        .frame(minHeight: Spacing.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat.replyOption")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
