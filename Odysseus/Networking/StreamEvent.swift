import Foundation

/// A single decoded SSE payload from /api/chat_stream.
///
/// The server emits newline-delimited `data: {json}` frames. Most frames are
/// either a text token (`{"delta": "..."}`, optionally `"thinking": true` for
/// reasoning tokens) or a structured event tagged with `"type"`. We decode the
/// fields we care about and ignore the long tail of advanced-feature events.
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

    struct ErrorBody: Decodable { var message: String? }

    enum CodingKeys: String, CodingKey {
        case delta, thinking, type, name, tool, model, requested, actual
        case tokens, tps, status, text, error, detail
    }

    var toolName: String? { name ?? tool }
    var modelName: String? { actual ?? model ?? requested }

    var errorMessage: String? {
        if let t = text, status ?? 0 >= 400 { return t }
        if let m = error?.message { return m }
        if let d = detail { return d }
        return nil
    }
}

/// High-level events the chat view model reacts to.
enum ChatStreamUpdate {
    case textDelta(String)
    case thinkingDelta(String)
    case toolStart(String)
    case modelResolved(String)
    case error(String)
    case done
}
