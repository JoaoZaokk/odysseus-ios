import Foundation

// Ported from the Open WebUI client (OpenWebUIKit/OWToolCalls.swift), written
// for the same report: Gemma 4 through LM Studio writing its tool call into the
// reply text. The Odysseus server parses and strips these in agent mode
// (src/tool_parsing.py), but plain chat mode streams the model's text as it
// comes and saves it that way, so a call written out there reached the bubble,
// the TTS and the history. The server runs the search; this side only hides.

/// A function call the model wrote out as text (see `ToolCallText`).
struct ToolCall: Sendable, Equatable {
    var name: String
}

/// Tool calls a model wrote into its *text* instead of the structured field.
///
/// Gemma served by LM Studio does this some of the time — the server's parser
/// misses its `<|tool_call>call:search_web{…}<tool_call|>` and the call reaches
/// the client as ordinary content — and Qwen/Hermes-style templates do the same
/// with `<tool_call>{"name": …}</tool_call>`. Shown, it is a line of gibberish
/// in the chat; spoken, it is worse; saved, it becomes an example the model
/// copies on every later turn.
enum ToolCallText {

    static let openers = ["<|tool_call|>", "<|tool_call>", "<tool_call>", "<tool_calls>",
                          "<function_call>", "[TOOL_CALLS]"]
    static let closers = ["<|/tool_call|>", "<tool_call|>", "</tool_call>", "</tool_calls>",
                          "</function_call>"]

    /// `text` without any tool-call block in it (code is left alone).
    /// For history: the server saves a plain-chat reply with its call in it.
    static func stripped(_ text: String) -> String {
        guard mayContainCall(text) else { return text }
        var filter = ToolCallFilter()
        var clean = filter.feed(text)
        clean += filter.finish()
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cheap pre-check, so ordinary text never runs through the filter.
    static func mayContainCall(_ text: String) -> Bool {
        if openers.contains(where: { text.contains($0) }) { return true }
        return untaggedCallStart(text.drop(while: \.isWhitespace)) != nil
    }

    /// `call:name{` at the very start of a reply: Gemma's call with the special
    /// tokens around it dropped by the server's detokenizer.
    static func untaggedCallStart(_ text: Substring) -> String? {
        guard text.hasPrefix("call:") else { return nil }
        let rest = text.dropFirst(5)
        let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }
        guard !name.isEmpty, rest.dropFirst(name.count).first == "{" else { return nil }
        return String(name)
    }

    /// The calls named inside one block. Empty when it holds no recognisable call.
    static func parse(_ body: String) -> [ToolCall] {
        let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("{") || t.hasPrefix("["),
           let json = try? JSONSerialization.jsonObject(with: Data(t.utf8)) {
            let names = ((json as? [Any]) ?? [json]).compactMap { item -> String? in
                guard let o = item as? [String: Any] else { return nil }
                return ((o["function"] as? [String: Any]) ?? o)["name"] as? String
            }
            if !names.isEmpty { return names.map(ToolCall.init(name:)) }
        }
        // Gemma: `call:name{args}`; Mistral after [TOOL_CALLS]: `name[ARGS]{args}`;
        // or a bare `name{args}` / `name(args)`.
        var rest = Substring(t)
        if rest.hasPrefix("call:") { rest = rest.dropFirst(5) }
        let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }
        guard !name.isEmpty else { return [] }
        var args = rest.dropFirst(name.count)
        if args.hasPrefix("[ARGS]") { args = args.dropFirst(6) }
        guard let first = args.first, first == "{" || first == "(" else { return [] }
        return [ToolCall(name: String(name))]
    }
}

/// Streaming side of `ToolCallText`: feed it the reply as it arrives and it
/// hands back only what is safe to show and speak, holding back anything that
/// could still turn out to be the start of a tool call.
struct ToolCallFilter: Sendable {
    private(set) var calls: [ToolCall] = []
    private var buffer = ""
    private var callBody = ""
    private var inCall = false
    /// The untagged form ends when its braces balance, not on a closing tag.
    private var untagged = false
    /// Inside a ``` block. A model explaining the format writes it in code,
    /// and that is the answer, not a call.
    private var inFence = false
    private var emittedAny = false
    /// Last character handed out, for a tag that opens the next chunk right
    /// after a backtick.
    private var lastShown: Character?
    private static let fence = "```"

    init() {}

    /// The part of everything fed so far that can be shown.
    mutating func feed(_ chunk: String) -> String {
        buffer += chunk
        var out = ""
        while true {
            if inCall {
                if untagged {
                    guard let end = Self.balancedEnd(buffer) else { return finishOut(out) }
                    callBody = String(buffer[..<end])
                    buffer = String(buffer[end...])
                    closeCall()
                    continue
                }
                if let (range, _) = Self.firstMatch(of: ToolCallText.closers, in: buffer) {
                    callBody += buffer[..<range.lowerBound]
                    buffer = String(buffer[range.upperBound...])
                    closeCall()
                    continue
                }
                return finishOut(out)
            }
            if inFence {
                guard let end = buffer.range(of: Self.fence) else {
                    let keep = Self.trailingBackticks(buffer)
                    out += buffer.dropLast(keep)
                    buffer = String(buffer.suffix(keep))
                    return finishOut(out)
                }
                out += buffer[..<end.upperBound]
                buffer = String(buffer[end.upperBound...])
                inFence = false
                continue
            }
            // Gemma with its special tokens dropped: a reply that *starts* with
            // `call:name{`. Only at the very start — anywhere else it is prose.
            if !emittedAny && out.isEmpty {
                let lead = buffer.drop(while: \.isWhitespace)
                if ToolCallText.untaggedCallStart(lead) != nil {
                    buffer = String(lead); inCall = true; untagged = true; callBody = ""
                    continue
                }
                if Self.couldStillBeUntaggedCall(lead) { return "" }
            }
            let opener = Self.firstMatch(of: ToolCallText.openers, in: buffer)
            if let open = buffer.range(of: Self.fence),
               opener.map({ open.lowerBound < $0.0.lowerBound }) ?? true {
                out += buffer[..<open.upperBound]
                buffer = String(buffer[open.upperBound...])
                inFence = true
                continue
            }
            if let (range, _) = opener {
                let before = range.lowerBound == buffer.startIndex
                    ? (out.last ?? lastShown) : buffer[buffer.index(before: range.lowerBound)]
                // `<tool_call>` in inline code names the tag; it calls nothing.
                if before == "`" {
                    out += buffer[..<range.upperBound]
                    buffer = String(buffer[range.upperBound...])
                    continue
                }
                out += buffer[..<range.lowerBound]
                buffer = String(buffer[range.upperBound...])
                inCall = true; untagged = false; callBody = ""
                continue
            }
            // Keep back a tail that is the beginning of an opener or a fence.
            let keep = max(Self.partialOpenerTail(buffer), Self.trailingBackticks(buffer))
            out += buffer.dropLast(keep)
            buffer = String(buffer.suffix(keep))
            return finishOut(out)
        }
    }

    /// End of the reply: whatever was held back. An unclosed call is still a call.
    mutating func finish() -> String {
        if inCall {
            callBody += buffer
            buffer = ""
            closeCall()
            return ""
        }
        let rest = buffer
        buffer = ""
        return finishOut(rest)
    }

    private mutating func finishOut(_ out: String) -> String {
        if let c = out.last { emittedAny = true; lastShown = c }
        return out
    }

    private mutating func closeCall() {
        let parsed = ToolCallText.parse(callBody)
        // Text between the tags that is not a call at all is still the model's
        // scaffolding, never something for the user — dropped either way, but
        // only a real call asks for a search.
        calls += parsed
        callBody = ""; inCall = false; untagged = false
    }

    /// `lead` is empty, a prefix of `call:`, or `call:` plus a name still
    /// waiting for its `{` — not yet decidable.
    private static func couldStillBeUntaggedCall(_ lead: Substring) -> Bool {
        if lead.isEmpty { return true }
        if lead.count < 5 { return "call:".hasPrefix(lead) }
        guard lead.hasPrefix("call:") else { return false }
        let name = lead.dropFirst(5)
        return name.count < 64 && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }
    }

    private static func firstMatch(of needles: [String], in s: String) -> (Range<String.Index>, String)? {
        var best: (Range<String.Index>, String)?
        for n in needles {
            if let r = s.range(of: n), best == nil || r.lowerBound < best!.0.lowerBound
                || (r.lowerBound == best!.0.lowerBound && n.count > best!.1.count) {
                best = (r, n)
            }
        }
        return best
    }

    private static func partialOpenerTail(_ s: String) -> Int {
        let maxLen = ToolCallText.openers.map(\.count).max() ?? 0
        for len in stride(from: min(maxLen - 1, s.count), through: 1, by: -1) {
            let tail = s.suffix(len)
            if ToolCallText.openers.contains(where: { $0.hasPrefix(tail) }) { return len }
        }
        return 0
    }

    /// Up to two backticks at the end: a fence may still be arriving.
    private static func trailingBackticks(_ s: String) -> Int {
        min(2, s.reversed().prefix { $0 == "`" }.count)
    }

    /// Index just past the `}` that balances the first `{`, skipping strings.
    private static func balancedEnd(_ s: String) -> String.Index? {
        var depth = 0
        var inString = false
        var escaped = false
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "{" {
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0 { return s.index(after: i) }
            }
            i = s.index(after: i)
        }
        return nil
    }
}
