import Foundation

/// A single decoded SSE payload from /api/chat_stream.
///
/// The server emits newline-delimited `data: {json}` frames. Most frames are
/// either a text token (`{"delta": "..."}`, optionally `"thinking": true` for
/// reasoning tokens) or a structured event tagged with `"type"`. We decode the
/// fields we care about and ignore the long tail of advanced-feature events.
///
/// Decoding is field-by-field and lenient on purpose: the same key carries
/// different shapes across event types (`data` is an object on `context_trimmed`
/// but an array on `web_sources`), and a synthesized decoder would throw on the
/// mismatch and drop the whole frame.
struct StreamEvent: Decodable {
    var delta: String?
    var thinking: Bool?
    var type: String?

    // tool_* events
    var name: String?      // tool name
    var tool: String?

    // model_info / model_actual
    var model: String?
    var requested: String?
    var actual: String?

    // metrics
    var tokens: Int?
    var tps: Double?

    // error frames
    var status: Int?
    var text: String?
    var error: ErrorBody?
    var detail: String?

    // context_trimmed (payload nested under `data`) / compacted (top level)
    var trim: TrimData?
    var contextLength: Int?

    // agent guards
    var limit: Int?        // budget_exceeded
    var used: Int?         // budget_exceeded
    var rounds: Int?       // rounds_exhausted

    struct ErrorBody: Decodable { var message: String? }

    struct TrimData: Decodable {
        var messagesBefore: Int?
        var messagesAfter: Int?
        var tokensBefore: Int?
        var tokensAfter: Int?
        var contextLength: Int?

        enum CodingKeys: String, CodingKey {
            case messagesBefore = "messages_before"
            case messagesAfter  = "messages_after"
            case tokensBefore   = "tokens_before"
            case tokensAfter    = "tokens_after"
            case contextLength  = "context_length"
        }
    }

    enum CodingKeys: String, CodingKey {
        case delta, thinking, type, name, tool, model, requested, actual
        case tokens, tps, status, text, error, detail
        case data, limit, used, rounds
        case contextLength = "context_length"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        delta    = try? c.decodeIfPresent(String.self, forKey: .delta)
        thinking = try? c.decodeIfPresent(Bool.self, forKey: .thinking)
        type     = try? c.decodeIfPresent(String.self, forKey: .type)
        name     = try? c.decodeIfPresent(String.self, forKey: .name)
        tool     = try? c.decodeIfPresent(String.self, forKey: .tool)
        model    = try? c.decodeIfPresent(String.self, forKey: .model)
        requested = try? c.decodeIfPresent(String.self, forKey: .requested)
        actual   = try? c.decodeIfPresent(String.self, forKey: .actual)
        tokens   = try? c.decodeIfPresent(Int.self, forKey: .tokens)
        tps      = try? c.decodeIfPresent(Double.self, forKey: .tps)
        status   = try? c.decodeIfPresent(Int.self, forKey: .status)
        text     = try? c.decodeIfPresent(String.self, forKey: .text)
        error    = try? c.decodeIfPresent(ErrorBody.self, forKey: .error)
        detail   = try? c.decodeIfPresent(String.self, forKey: .detail)
        trim     = try? c.decodeIfPresent(TrimData.self, forKey: .data)
        contextLength = try? c.decodeIfPresent(Int.self, forKey: .contextLength)
        limit    = try? c.decodeIfPresent(Int.self, forKey: .limit)
        used     = try? c.decodeIfPresent(Int.self, forKey: .used)
        rounds   = try? c.decodeIfPresent(Int.self, forKey: .rounds)
    }

    var toolName: String? { name ?? tool }
    var modelName: String? { actual ?? model ?? requested }

    var errorMessage: String? {
        if let t = text, status ?? 0 >= 400 { return t }
        if let m = error?.message { return m }
        if let d = detail { return d }
        return nil
    }

    /// The notice this frame carries, if it is one of the server's
    /// context/agent-guard events. Returns nil for every other event type.
    var notice: ChatNotice? {
        switch type {
        case "context_trimmed":
            let before = trim?.messagesBefore, after = trim?.messagesAfter
            if let b = before, let a = after, b > a { return ChatNotice(kind: .contextTrimmed(removed: b - a)) }
            return ChatNotice(kind: .contextTrimmed(removed: 0))
        case "compacted":
            return ChatNotice(kind: .compacted)
        case "rounds_exhausted":
            return ChatNotice(kind: .roundsExhausted(rounds: rounds ?? 0))
        case "budget_exceeded":
            return ChatNotice(kind: .budgetExceeded(limit: limit ?? 0, used: used ?? 0))
        case "loop_breaker_triggered":
            return ChatNotice(kind: .loopBreaker)
        case "intent_nudge_exhausted":
            return ChatNotice(kind: .intentNudgeExhausted)
        default:
            return nil
        }
    }
}

/// A non-fatal notice raised mid-stream: the server dropped old messages to fit
/// the context window, or an agent guard cut the run short. Both otherwise look
/// like the assistant silently forgetting or giving up, so the notice outlives
/// the stream instead of riding the transient `toolStatus`.
///
/// The server ships an English `message` on some of these; we ignore it and
/// build the text client-side so it lands in the user's language.
struct ChatNotice: Identifiable, Hashable {
    enum Kind: Hashable {
        case contextTrimmed(removed: Int)
        case compacted
        case roundsExhausted(rounds: Int)
        case budgetExceeded(limit: Int, used: Int)
        case loopBreaker
        case intentNudgeExhausted
    }

    let id = UUID()
    let kind: Kind

    static func == (a: ChatNotice, b: ChatNotice) -> Bool { a.kind == b.kind }
    func hash(into h: inout Hasher) { h.combine(kind) }

    var icon: String {
        switch kind {
        case .contextTrimmed, .compacted: return "scissors"
        case .roundsExhausted, .budgetExceeded: return "gauge.with.dots.needle.33percent"
        case .loopBreaker, .intentNudgeExhausted: return "exclamationmark.arrow.circlepath"
        }
    }
}

/// High-level events the chat view model reacts to.
enum ChatStreamUpdate {
    case textDelta(String)
    case thinkingDelta(String)
    case toolStart(String)
    case modelResolved(String)
    case notice(ChatNotice)
    case error(String)
    case done
}
