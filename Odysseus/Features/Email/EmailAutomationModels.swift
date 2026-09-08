import Foundation

/// The auto-reply block of `GET /api/email/config?account_id=…`, merged
/// per account by the server. Only these keys are ever written back; the
/// credentials that share the endpoint never leave the server.
struct EmailAutomationConfig: Decodable, Equatable {
    var enabled = false
    var start = ""
    var end = ""
    var subject = ""
    var message = ""
    var cooldown = "period"
    var excludeAutomated = true
    var pauseNotifications = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case enabled = "email_auto_reply", start = "email_auto_reply_start", end = "email_auto_reply_end"
        case subject = "email_auto_reply_subject", message = "email_auto_reply_message", cooldown = "email_auto_reply_cooldown"
        case excludeAutomated = "email_auto_reply_exclude_automated", pauseNotifications = "email_auto_reply_pause_notifications"
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        start = (try? c.decode(String.self, forKey: .start)) ?? ""
        end = (try? c.decode(String.self, forKey: .end)) ?? ""
        subject = (try? c.decode(String.self, forKey: .subject)) ?? ""
        message = (try? c.decode(String.self, forKey: .message)) ?? ""
        cooldown = (try? c.decode(String.self, forKey: .cooldown)) ?? "period"
        excludeAutomated = (try? c.decode(Bool.self, forKey: .excludeAutomated)) ?? true
        pauseNotifications = (try? c.decode(Bool.self, forKey: .pauseNotifications)) ?? false
    }

    /// The PUT body: the auto-reply keys and nothing else.
    func payload(accountId: String) -> [String: Any] {
        ["email_auto_reply": enabled, "email_auto_reply_start": start, "email_auto_reply_end": end,
         "email_auto_reply_subject": subject, "email_auto_reply_message": message,
         "email_auto_reply_cooldown": cooldown, "email_auto_reply_exclude_automated": excludeAutomated,
         "email_auto_reply_pause_notifications": pauseNotifications,
         "email_auto_reply_scope": "account", "email_auto_reply_account_id": accountId]
    }
}

struct UnsubscribeCandidate: Decodable, Identifiable {
    var id: String          // the message uid
    var folder: String
    var subject: String
    var fromName: String
    var fromAddress: String
    var score: Int
    var canExecute: Bool
    var duplicateCount: Int
    var duplicateUids: [String]
    enum CodingKeys: String, CodingKey {
        case uid, folder, subject, fromName = "from_name", fromAddress = "from_address", score
        case canExecute = "can_execute", duplicateCount = "duplicate_count", duplicateUids = "duplicate_uids"
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .uid) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .uid) { id = String(i) } else { id = UUID().uuidString }
        folder = (try? c.decode(String.self, forKey: .folder)) ?? "INBOX"
        subject = (try? c.decode(String.self, forKey: .subject)) ?? ""
        fromName = (try? c.decode(String.self, forKey: .fromName)) ?? ""
        fromAddress = (try? c.decode(String.self, forKey: .fromAddress)) ?? ""
        score = (try? c.decode(Int.self, forKey: .score)) ?? 0
        canExecute = (try? c.decode(Bool.self, forKey: .canExecute)) ?? false
        duplicateCount = (try? c.decode(Int.self, forKey: .duplicateCount)) ?? 0
        if let s = try? c.decode([String].self, forKey: .duplicateUids) { duplicateUids = s }
        else if let i = try? c.decode([Int].self, forKey: .duplicateUids) { duplicateUids = i.map(String.init) }
        else { duplicateUids = [] }
    }
}

struct UnsubscribeScan: Decodable {
    var success: Bool
    var candidates: [UnsubscribeCandidate]
    var total: Int
    var scanned: Int
    var error: String?
    enum CodingKeys: String, CodingKey { case success, candidates, total, scanned, error }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        success = (try? c.decode(Bool.self, forKey: .success)) ?? false
        candidates = (try? c.decode([UnsubscribeCandidate].self, forKey: .candidates)) ?? []
        total = (try? c.decode(Int.self, forKey: .total)) ?? candidates.count
        scanned = (try? c.decode(Int.self, forKey: .scanned)) ?? 0
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}
