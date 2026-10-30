import Foundation

/// A reply's text before it is drawn as Markdown. Models write HTML for layout
/// the web renders and drops — `<div style="text-align: center;">`, `<br>` —
/// and the Markdown view printed those tags as text. Layout tags go; a break
/// tag becomes a newline. Code (fenced or inline) is never touched.
enum ReplyMarkup {
    private static let layoutTag = try! NSRegularExpression(
        pattern: #"</?(?:div|center|span|p|section|font|small|big)\b[^>]*>"#, options: [.caseInsensitive])
    private static let breakTag = try! NSRegularExpression(pattern: #"<br\s*/?>"#, options: [.caseInsensitive])

    static func clean(_ text: String) -> String {
        guard text.contains("<") else { return text }
        var out: [String] = []
        var inFence = false
        var inSVG = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle(); out.append(line); continue
            }
            if inFence { out.append(line); continue }
            // A bare <svg>…</svg> in the text is drawn on the web; here it
            // becomes an svg block, which the chat draws too.
            if !inSVG, trimmed.lowercased().hasPrefix("<svg") {
                inSVG = true; out.append("```svg")
            }
            if inSVG {
                out.append(line)
                if trimmed.lowercased().contains("</svg>") { inSVG = false; out.append("```") }
                continue
            }
            let cleaned = outsideInlineCode(line) { part in
                let range = NSRange(part.startIndex..., in: part)
                let noBreaks = breakTag.stringByReplacingMatches(in: part, range: range, withTemplate: "\n")
                return layoutTag.stringByReplacingMatches(in: noBreaks, range: NSRange(noBreaks.startIndex..., in: noBreaks),
                                                          withTemplate: "")
            }
            // A line that held only a layout tag would leave a stray blank line.
            if cleaned.trimmingCharacters(in: .whitespaces).isEmpty, !trimmed.isEmpty { continue }
            out.append(cleaned)
        }
        return out.joined(separator: "\n")
    }

    /// Applies `transform` to the parts of a line outside `inline code`.
    private static func outsideInlineCode(_ line: String, _ transform: (String) -> String) -> String {
        guard line.contains("`") else { return transform(line) }
        var result = "", buffer = "", inCode = false
        for ch in line {
            if ch == "`" {
                result += inCode ? buffer + "`" : transform(buffer) + "`"
                buffer = ""; inCode.toggle()
            } else {
                buffer.append(ch)
            }
        }
        return result + (inCode ? buffer : transform(buffer))
    }
}
