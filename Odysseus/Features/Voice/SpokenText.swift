import Foundation

/// Turning written text into something worth saying out loud.
///
/// Two jobs, both pure functions of their input: deciding what a sentence
/// *sounds* like once markdown is removed, and deciding *where* a reply that is
/// still being written can be cut so speaking starts before generation ends.
///
/// This lived inside `SpeechManager` and `VoiceConversation` as `nonisolated
/// static` members — the `nonisolated` being the tell, since it existed only to
/// escape the `@MainActor` of a class that had nothing to do with text. None of
/// it touches audio, a network or a turn, and all of it is what the test suite
/// actually pins.
enum SpokenText {

    // MARK: - What gets said

    /// Whether `text` still says anything once markdown is stripped.
    ///
    /// Callers that change state before queueing (the voice loop enters
    /// `.speaking` and reconfigures the audio session) must ask first: a
    /// sentence made only of markup — a fence, a bare `**`, a horizontal rule —
    /// is dropped by the queue, which left the loop speaking with nothing to
    /// speak and no way to end the turn.
    static func isSpeakable(_ text: String) -> Bool { !strip(text).isEmpty }

    /// What the engines will actually be asked to say.
    static func strip(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "```[\\s\\S]*?```", with: L(" (bloco de código) "), options: .regularExpression)
        t = t.replacingOccurrences(of: "`([^`]*)`", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\*\\*([^*]*)\\*\\*", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "[*_#>]", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
        t = spokenTableRow(t) ?? t
        let cleaned = t.trimmingCharacters(in: .whitespacesAndNewlines)
        // Whatever is left with no letter and no digit is markup the rules above
        // didn't recognize: an unclosed code fence (the fence rule needs both
        // ends, so a lone ``` survives as a stray backtick), a horizontal rule,
        // a bare bullet. Speaking it produces a garbage utterance — and it also
        // defeats `isSpeakable`, letting the voice loop commit to .speaking for
        // a chunk that says nothing.
        return cleaned.contains(where: { $0.isLetter || $0.isNumber }) ? cleaned : ""
    }

    /// A markdown table row read as a list of cells, or nil when this is not a
    /// table row at all.
    ///
    /// Table rows arrive as chunks of their own (the sentence cutter breaks on
    /// newlines) and were being read out verbatim, pipes and all. Nobody hit it
    /// until a reply came back with a comparison table, and then the voice spent
    /// half a minute reciting "Duração 4 anos 1914-1918 6 anos". A separator row
    /// carries no words at all; a data row is a list of cells, so it is spoken
    /// as one.
    ///
    /// The test is the leading pipe, not merely containing one: every markdown
    /// row starts with a pipe, while an ordinary sentence can hold one in
    /// passing — "roda ls | grep erro" was being shredded into cells and read
    /// back as "roda ls, grep erro".
    private static func spokenTableRow(_ t: String) -> String? {
        guard t.trimmingCharacters(in: .whitespaces).hasPrefix("|") else { return nil }
        let cells = t.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let isRule = !cells.isEmpty && cells.allSatisfy { cell in
            cell.allSatisfy { $0 == "-" || $0 == ":" }
        }
        return isRule ? "" : cells.joined(separator: ", ")
    }

    // MARK: - Where a still-arriving reply can be cut

    /// Offset just past the first sentence terminator that is followed by
    /// whitespace. Requiring the space keeps "3.5" and "R$ 1.200,00" intact.
    static func sentenceCut(in s: String) -> Int? {
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
    /// clause cut can land a falling intonation mid-sentence. That is the trade
    /// being made deliberately — in a hands-free loop the wait before the first
    /// word is what the user actually notices.
    static let openingSoft = 60
    static let openingHard = 140

    static func openingCut(in s: String) -> Int? {
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
}
