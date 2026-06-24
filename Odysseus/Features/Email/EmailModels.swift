import Foundation

/// A message row from GET /api/email/list (`{emails:[...], total, error}`).
struct EmailMessage: Decodable, Identifiable, Hashable, Sendable {
    var uid: String
    var subject: String
    var fromName: String
    var fromAddress: String
    var date: String?
    var isRead: Bool
    var hasAttachments: Bool

    var id: String { uid }

    enum CodingKeys: String, CodingKey {
        case uid, subject
        case fromName = "from_name"
        case fromAddress = "from_address"
        case from, sender
        case date
        case isRead = "is_read"
        case seen
        case hasAttachments = "has_attachments"
        case attachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .uid) { uid = s }
        else if let i = try? c.decode(Int.self, forKey: .uid) { uid = String(i) }
        else { uid = UUID().uuidString }
        subject = (try? c.decode(String.self, forKey: .subject)) ?? "(sem assunto)"
        fromName = (try? c.decode(String.self, forKey: .fromName))
            ?? (try? c.decode(String.self, forKey: .from))
            ?? (try? c.decode(String.self, forKey: .sender)) ?? ""
        fromAddress = (try? c.decode(String.self, forKey: .fromAddress)) ?? ""
        date = try? c.decodeIfPresent(String.self, forKey: .date)
        isRead = (try? c.decode(Bool.self, forKey: .isRead))
            ?? (try? c.decode(Bool.self, forKey: .seen)) ?? false
        if let b = try? c.decode(Bool.self, forKey: .hasAttachments) {
            hasAttachments = b
        } else if let arr = try? c.decode([AnyDecodable].self, forKey: .attachments) {
            hasAttachments = !arr.isEmpty
        } else {
            hasAttachments = false
        }
    }

    var displayFrom: String { fromName.isEmpty ? fromAddress : fromName }
}

/// Full message from GET /api/email/read/:uid.
struct EmailDetail: Decodable, Sendable {
    var subject: String
    var fromName: String
    var fromAddress: String
    var date: String?
    var body: String
    var to: String?

    enum CodingKeys: String, CodingKey {
        case subject, date, to, body
        case bodyHTML = "body_html"
        case fromName = "from_name"
        case fromAddress = "from_address"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subject = (try? c.decode(String.self, forKey: .subject)) ?? ""
        fromName = (try? c.decode(String.self, forKey: .fromName)) ?? ""
        fromAddress = (try? c.decode(String.self, forKey: .fromAddress)) ?? ""
        date = try? c.decodeIfPresent(String.self, forKey: .date)
        to = try? c.decodeIfPresent(String.self, forKey: .to)
        // Prefer plain text; fall back to HTML stripped of tags.
        if let t = try? c.decode(String.self, forKey: .body), !t.isEmpty {
            body = t
        } else if let h = try? c.decode(String.self, forKey: .bodyHTML) {
            body = h.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        } else {
            body = ""
        }
    }
}

/// The list endpoint may report a backend error (e.g. no mail account).
struct EmailListResponse: Decodable {
    var emails: [EmailMessage]
    var total: Int
    var error: String?

    enum CodingKeys: String, CodingKey { case emails, total, error }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        emails = (try? c.decode([EmailMessage].self, forKey: .emails)) ?? []
        total = (try? c.decode(Int.self, forKey: .total)) ?? emails.count
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

/// Tiny type-erased decodable for counting unknown-shaped arrays.
struct AnyDecodable: Decodable { init(from decoder: Decoder) throws {} }
