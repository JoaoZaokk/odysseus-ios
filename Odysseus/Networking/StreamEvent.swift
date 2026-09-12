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

    // ask_user (payload nested under `data`, same key as the trim above —
    // only one of the two ever decodes for a given frame).
    var ask: AskUser?

    // tool_approval_resolved
    var decision: String?

    // agent guards
    var limit: Int?        // budget_exceeded
    var used: Int?         // budget_exceeded
    var rounds: Int?       // rounds_exhausted

    /// `error` is a plain string in most of the server's error frames
    /// (`{"error": "Read timeout", "status": 504}`, llm_core.py) and an object
    /// (`{"error": {"message": …}}`) in the rest. 1.9 only decoded the object,
    /// so 21 of the live server's 25 error frames reached the user as the
    /// generic "Erro no stream".
    struct ErrorBody: Decodable {
        var message: String?
        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(),
               let s = try? single.decode(String.self) { message = s; return }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            message = try c.decodeIfPresent(String.self, forKey: .message)
        }
        private enum CodingKeys: String, CodingKey { case message }
    }

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
        case data, limit, used, rounds, decision
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
        ask      = try? c.decodeIfPresent(AskUser.self, forKey: .data)
        decision = try? c.decodeIfPresent(String.self, forKey: .decision)
        contextLength = try? c.decodeIfPresent(Int.self, forKey: .contextLength)
        limit    = try? c.decodeIfPresent(Int.self, forKey: .limit)
        used     = try? c.decodeIfPresent(Int.self, forKey: .used)
        rounds   = try? c.decodeIfPresent(Int.self, forKey: .rounds)
    }

    var toolName: String? { name ?? tool }
    var modelName: String? { actual ?? model ?? requested }

    /// Only consulted on an error frame (`event: error` or `status >= 400`), so
    /// `text` is the message whatever the status — some frames carry no status.
    var errorMessage: String? {
        if let m = error?.message, !m.isEmpty { return m }
        if let d = detail, !d.isEmpty { return d }
        if let t = text, !t.isEmpty { return t }
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
        /// The user denied a tool approval — the run stops there and the server
        /// sends no reply text, so without this the turn looks like a failure.
        case approvalDenied
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
        case .approvalDenied: return "hand.raised"
        }
    }
}

/// The assistant's question back to the user: `{"type":"ask_user","data":{…}}`.
///
/// Two different things ride this one event. A plain multiple-choice question
/// (the `ask_user` tool) ENDS the agent's turn — the answer is simply the next
/// user message, so a client that ignores the frame leaves the user staring at
/// a reply that never came. A tool approval (`kind == "tool_approval"`) also
/// ends the turn, but its answer is not a message at all: the decision rides
/// the control-plane fields of the next stream, keyed by `approval_id`.
///
/// The same payload is persisted on the assistant message
/// (`metadata.tool_events[].ask_user`), which is how a reopened chat gets its
/// card back.
struct AskUser: Decodable, Hashable, Identifiable {
    struct Option: Decodable, Hashable, Identifiable {
        var label: String
        var description: String?
        /// Approvals only: "approve" | "approve_task" | "deny".
        var value: String?
        var id: String { label }
    }

    /// What a tool approval is asking permission for. Rendered verbatim — the
    /// user is authorizing this exact action, so it must not be paraphrased.
    struct Action: Decodable, Hashable {
        var tool: String?
        var content: String?
        var effects: [String]?
        var workspace: String?
        var documentID: String?
        enum CodingKeys: String, CodingKey {
            case tool, content, effects, workspace
            case documentID = "document_id"
        }
    }

    var question: String
    var description: String?
    var options: [Option]
    var multi: Bool
    var kind: String?
    var approvalID: String?
    var action: Action?
    /// Set by the server once an approval has been consumed. A resolved card is
    /// history, not a prompt — it never comes back on screen.
    var resolved: String?

    /// Identity is the payload, not a fresh UUID: the same card can arrive live
    /// and then again from history, and the two must not stack.
    var id: String { approvalID ?? question }

    var isApproval: Bool { kind == "tool_approval" && approvalID?.isEmpty == false }
    /// The server caps this at 6; a card with fewer than 2 is malformed and the
    /// web drops it, so we do too.
    var isRenderable: Bool { !question.isEmpty && options.count >= 2 && resolved == nil }

    enum CodingKeys: String, CodingKey {
        case question, description, options, multi, kind, action, resolved
        case approvalID = "approval_id"
    }

    init(question: String, description: String? = nil, options: [Option],
         multi: Bool = false, kind: String? = nil, approvalID: String? = nil,
         action: Action? = nil, resolved: String? = nil) {
        self.question = question; self.description = description
        self.options = options; self.multi = multi; self.kind = kind
        self.approvalID = approvalID; self.action = action; self.resolved = resolved
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        question = (try? c.decode(String.self, forKey: .question)) ?? ""
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        // Options are objects, but the tool also accepts bare strings.
        if let objs = try? c.decode([Option].self, forKey: .options) {
            options = objs
        } else if let strs = try? c.decode([String].self, forKey: .options) {
            options = strs.map { Option(label: $0) }
        } else {
            options = []
        }
        multi = (try? c.decode(Bool.self, forKey: .multi)) ?? false
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        approvalID = try? c.decodeIfPresent(String.self, forKey: .approvalID)
        action = try? c.decodeIfPresent(Action.self, forKey: .action)
        resolved = try? c.decodeIfPresent(String.self, forKey: .resolved)
    }
}

/// High-level events the chat view model reacts to.
enum ChatStreamUpdate {
    case textDelta(String)
    case thinkingDelta(String)
    case toolStart(String)
    case modelResolved(String)
    case notice(ChatNotice)
    /// The turn ended on a question — the reply is the card, not more text.
    case askUser(AskUser)
    /// `X-Odysseus-Run-Id` from the chat_stream response headers: upstream ≥
    /// c436930 only honours `/api/chat/stop` when it carries this id back.
    case runStarted(String)
    case error(String)
    case done
}
