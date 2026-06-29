import Foundation

/// An email account from GET /api/email/accounts.
struct EmailAccount: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var fromAddress: String
    var imapHost: String
    var imapPort: Int
    var imapUser: String
    var smtpHost: String
    var isDefault: Bool
    var hasSMTPPassword: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case fromAddress = "from_address"
        case imapHost = "imap_host"
        case imapPort = "imap_port"
        case imapUser = "imap_user"
        case smtpHost = "smtp_host"
        case isDefault = "is_default"
        case hasSMTPPassword = "has_smtp_password"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) }
        else { id = UUID().uuidString }
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        fromAddress = (try? c.decode(String.self, forKey: .fromAddress)) ?? ""
        imapHost = (try? c.decode(String.self, forKey: .imapHost)) ?? ""
        imapPort = (try? c.decode(Int.self, forKey: .imapPort)) ?? 993
        imapUser = (try? c.decode(String.self, forKey: .imapUser)) ?? ""
        smtpHost = (try? c.decode(String.self, forKey: .smtpHost)) ?? ""
        isDefault = (try? c.decode(Bool.self, forKey: .isDefault)) ?? false
        hasSMTPPassword = (try? c.decode(Bool.self, forKey: .hasSMTPPassword)) ?? false
    }

    var subtitle: String {
        let who = imapUser.isEmpty ? fromAddress : imapUser
        let server = imapHost.isEmpty ? "" : "\(imapHost):\(imapPort)"
        return [who, server].filter { !$0.isEmpty }.joined(separator: " — ")
    }
}

/// Body for POST /api/email/accounts and POST /api/email/accounts/test — the
/// exact field set the server's web form sends (see static/js/settings.js).
struct EmailAccountPayload: Encodable {
    var name: String
    var from_address: String
    var display_name: String
    var imap_host: String
    var imap_port: Int
    var imap_user: String
    var imap_starttls: Bool
    var smtp_host: String
    var smtp_port: Int
    var smtp_security: String   // "ssl" | "starttls" | "none"
    var smtp_user: String
    var is_default: Bool
    // Optional → Swift's synthesized Encodable omits these when nil, matching the
    // web form (a blank password keeps whatever the server already stored).
    var imap_password: String?
    var smtp_password: String?
}
