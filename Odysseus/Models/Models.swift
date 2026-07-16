import Foundation

/// Parses the ISO-8601 timestamps Odysseus emits (with fractional seconds,
/// optional `Z`) into an epoch interval for sorting/formatting.
enum ISODate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func parse(_ s: String) -> Double? {
        // Timezone-aware if it has a "Z", a "+", or a "-" after the date part
        // (a negative UTC offset, "…T09:30:00-03:00"); otherwise assume UTC.
        let aware = s.contains("Z") || s.contains("+") || s.dropFirst(10).contains("-")
        let str = aware ? s : s + "Z"
        if let d = withFraction.date(from: str) { return d.timeIntervalSince1970 }
        if let d = plain.date(from: str) { return d.timeIntervalSince1970 }
        return nil
    }
}

// MARK: - Auth

/// GET /api/auth/status
struct AuthStatus: Codable, Sendable {
    var configured: Bool
    var authenticated: Bool
    var username: String?
    var isAdmin: Bool

    enum CodingKeys: String, CodingKey {
        case configured, authenticated, username
        case isAdmin = "is_admin"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        configured = (try? c.decode(Bool.self, forKey: .configured)) ?? false
        authenticated = (try? c.decode(Bool.self, forKey: .authenticated)) ?? false
        username = try? c.decodeIfPresent(String.self, forKey: .username)
        isAdmin = (try? c.decode(Bool.self, forKey: .isAdmin)) ?? false
    }
}

/// POST /api/auth/login  body: {username, password, remember, totp_code?}
struct LoginRequest: Encodable {
    var username: String
    var password: String
    var remember: Bool = true
    var totp_code: String?
}

/// Login response is small; we mostly care about ok / detail / a 2FA signal.
struct LoginResponse: Decodable {
    var ok: Bool?
    var detail: String?
    var totpRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case ok, detail
        case totpRequired = "totp_required"
        case requires2fa = "requires_2fa"
        case totp = "totp"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try? c.decodeIfPresent(Bool.self, forKey: .ok)
        detail = try? c.decodeIfPresent(String.self, forKey: .detail)
        // The web client flips into TOTP mode on a few possible signals.
        let a = (try? c.decodeIfPresent(Bool.self, forKey: .totpRequired)) ?? false
        let b = (try? c.decodeIfPresent(Bool.self, forKey: .requires2fa)) ?? false
        let d = (try? c.decodeIfPresent(Bool.self, forKey: .totp)) ?? false
        totpRequired = a || b || d
    }
}

/// GET /api/auth/features
struct Features: Codable, Sendable, Equatable {
    var webSearch = false
    var webFetch = false
    var deepResearch = false
    var memory = false
    var documentEditor = false
    var rag = false
    var gallery = false

    enum CodingKeys: String, CodingKey {
        case webSearch = "web_search"
        case webFetch = "web_fetch"
        case deepResearch = "deep_research"
        case memory
        case documentEditor = "document_editor"
        case rag, gallery
    }

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        webSearch = (try? c.decode(Bool.self, forKey: .webSearch)) ?? false
        webFetch = (try? c.decode(Bool.self, forKey: .webFetch)) ?? false
        deepResearch = (try? c.decode(Bool.self, forKey: .deepResearch)) ?? false
        memory = (try? c.decode(Bool.self, forKey: .memory)) ?? false
        documentEditor = (try? c.decode(Bool.self, forKey: .documentEditor)) ?? false
        rag = (try? c.decode(Bool.self, forKey: .rag)) ?? false
        gallery = (try? c.decode(Bool.self, forKey: .gallery)) ?? false
    }
}

// MARK: - Models (LLMs)

/// GET /api/models — shape is verified against the live server; we decode
/// tolerantly so unexpected fields never break the picker.
struct ChatModel: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var endpointId: String?
    var endpointURL: String?

    enum CodingKeys: String, CodingKey {
        case id, name, model, label, title
        case endpointId = "endpoint_id"
    }

    init(id: String, name: String, endpointId: String? = nil, endpointURL: String? = nil) {
        self.id = id; self.name = name; self.endpointId = endpointId; self.endpointURL = endpointURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawId = (try? c.decode(String.self, forKey: .id))
            ?? (try? c.decode(String.self, forKey: .model))
            ?? ""
        id = rawId
        name = (try? c.decode(String.self, forKey: .name))
            ?? (try? c.decode(String.self, forKey: .label))
            ?? (try? c.decode(String.self, forKey: .title))
            ?? rawId
        endpointId = try? c.decodeIfPresent(String.self, forKey: .endpointId)
        if id.isEmpty { id = name }
    }
}

// MARK: - Sessions

/// One row in GET /api/sessions. Decoded leniently because the server may
/// return id as a string or number and timestamps in a few formats.
struct ChatSession: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var model: String?
    var updatedAt: Double?
    var pinned: Bool
    var archived: Bool

    enum CodingKeys: String, CodingKey {
        case id, sid, session_id
        case title, name
        case model
        case updatedAt = "updated_at"
        case lastMessageAt = "last_message_at"
        case updated, mtime
        case pinned, important
        case isImportant = "is_important"
        case archived
    }

    init(id: String, title: String, model: String? = nil, updatedAt: Double? = nil, pinned: Bool = false, archived: Bool = false) {
        self.id = id; self.title = title; self.model = model
        self.updatedAt = updatedAt; self.pinned = pinned; self.archived = archived
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = ChatSession.decodeID(c, keys: [.id, .sid, .session_id]) ?? UUID().uuidString
        // The server's primary title field is `name`.
        title = (try? c.decode(String.self, forKey: .name))
            ?? (try? c.decode(String.self, forKey: .title))
            ?? "Untitled"
        model = try? c.decodeIfPresent(String.self, forKey: .model)
        // Timestamps come as ISO-8601 strings (`last_message_at` / `updated_at`)
        // but tolerate epoch numbers too.
        updatedAt = ChatSession.timestamp(c, keys: [.lastMessageAt, .updatedAt, .updated, .mtime])
        // The server's "pinned" flag is `is_important`.
        pinned = (try? c.decode(Bool.self, forKey: .isImportant))
            ?? (try? c.decode(Bool.self, forKey: .pinned))
            ?? (try? c.decode(Bool.self, forKey: .important)) ?? false
        archived = (try? c.decode(Bool.self, forKey: .archived)) ?? false
    }

    private static func timestamp(_ c: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> Double? {
        for k in keys {
            if let d = try? c.decode(Double.self, forKey: k) { return d }
            if let s = try? c.decode(String.self, forKey: k), let d = ISODate.parse(s) { return d }
        }
        return nil
    }

    /// Short model label, e.g. "gemma-4-e2b" from a long path-style id.
    var shortModel: String? { model?.split(separator: "/").last.map(String.init) }

    private static func decodeID(_ c: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> String? {
        for k in keys {
            if let s = try? c.decode(String.self, forKey: k) { return s }
            if let i = try? c.decode(Int.self, forKey: k) { return String(i) }
        }
        return nil
    }
}

// MARK: - Messages

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
    case tool

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? "assistant"
        self = MessageRole(rawValue: raw.lowercased()) ?? .assistant
    }
}

/// A persisted message from GET /api/session/:id. Streaming messages are
/// represented by the same struct, built incrementally on the client.
struct Message: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var role: MessageRole
    var content: String
    var model: String?
    var thinking: String?
    var timestamp: Double?
    /// Attachment ids (served at /api/upload/{id}).
    var attachments: [String] = []

    enum CodingKeys: String, CodingKey {
        case id, mid
        case role
        case content, text
        case model
        case thinking, reasoning
        case timestamp, ts, created_at
        case metadata
        case attachments
    }

    /// Per-message metadata in GET /api/history: the model, timestamp, db id and
    /// the saved reasoning live here, not at the top level.
    struct Metadata: Decodable {
        var model: String?
        var timestamp: String?
        var dbID: String?
        /// The server saves the reasoning trace under `metadata.thinking`
        /// (it goes in with the rest of the metrics when the stream finishes),
        /// so a reopened chat only finds it here — never at the top level.
        var thinking: String?
        enum CodingKeys: String, CodingKey {
            case model, timestamp, thinking
            case dbID = "_db_id"
        }
    }

    init(id: String = UUID().uuidString,
         role: MessageRole,
         content: String,
         model: String? = nil,
         thinking: String? = nil,
         timestamp: Double? = nil,
         attachments: [String] = []) {
        self.id = id; self.role = role; self.content = content
        self.model = model; self.thinking = thinking; self.timestamp = timestamp
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let meta = try? c.decodeIfPresent(Metadata.self, forKey: .metadata)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) }
        else if let s = try? c.decode(String.self, forKey: .mid) { id = s }
        else { id = meta?.dbID ?? UUID().uuidString }
        role = (try? c.decode(MessageRole.self, forKey: .role)) ?? .assistant
        // `content` is usually a string, but multimodal messages send an array
        // of parts like [{type:"text", text:"..."}, {type:"image_url", ...}].
        if let s = try? c.decode(String.self, forKey: .content) {
            content = s
        } else if let parts = try? c.decode([ContentPart].self, forKey: .content) {
            content = parts.compactMap(\.text).joined(separator: "\n")
        } else if let s = try? c.decode(String.self, forKey: .text) {
            content = s
        } else {
            content = ""
        }
        model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? meta?.model
        thinking = (try? c.decodeIfPresent(String.self, forKey: .thinking))
            ?? (try? c.decodeIfPresent(String.self, forKey: .reasoning))
            ?? meta?.thinking
        timestamp = (try? c.decode(Double.self, forKey: .timestamp))
            ?? (try? c.decode(Double.self, forKey: .ts))
            ?? (try? c.decode(Double.self, forKey: .created_at))
            ?? meta?.timestamp.flatMap(ISODate.parse)
        // Attachments may be ["id", …] or [{"id": "…"}, …].
        if let ids = try? c.decode([String].self, forKey: .attachments) {
            attachments = ids
        } else if let objs = try? c.decode([AttachmentRef].self, forKey: .attachments) {
            attachments = objs.compactMap(\.id)
        } else {
            attachments = []
        }
    }

    private struct AttachmentRef: Decodable { var id: String? }
}

/// One element of a multimodal `content` array.
struct ContentPart: Decodable {
    var type: String?
    var text: String?
}

/// GET /api/history/:id — messages under `history`, plus the authoritative
/// `model`. Also tolerates a bare top-level array just in case.
struct SessionDetail: Decodable {
    var model: String?
    var messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model, messages, history, msgs
    }

    init(from decoder: Decoder) throws {
        if let arr = try? decoder.singleValueContainer().decode([Message].self) {
            messages = arr; model = nil; return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try? c.decodeIfPresent(String.self, forKey: .model)
        messages = (try? c.decode([Message].self, forKey: .history))
            ?? (try? c.decode([Message].self, forKey: .messages))
            ?? (try? c.decode([Message].self, forKey: .msgs))
            ?? []
    }
}

/// GET /api/default-chat — the user's default model/endpoint for new chats.
struct DefaultChat: Decodable, Sendable {
    var endpointURL: String
    var model: String
    var endpointID: String?

    enum CodingKeys: String, CodingKey {
        case endpointURL = "endpoint_url"
        case model
        case endpointID = "endpoint_id"
    }
}

/// POST /api/session response — we only need the new id.
struct CreateSessionResponse: Decodable {
    var id: String
    enum CodingKeys: String, CodingKey { case id, sid, session_id }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) }
        else if let s = try? c.decode(String.self, forKey: .sid) { id = s }
        else if let s = try? c.decode(String.self, forKey: .session_id) { id = s }
        else { id = "" }
    }
}
