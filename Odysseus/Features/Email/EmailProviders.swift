import Foundation

/// Known IMAP/SMTP providers — mirrors the server's web form
/// (`static/js/settings.js` PROVIDERS table) so the native app fills the exact
/// same hosts/ports and shows the same app-password guidance.
struct EmailProvider: Identifiable, Hashable {
    let id: String            // "icloud", "gmail", …; "" = Custom
    let label: String         // shown in the picker (brand names, not localized)
    let emailExample: String
    let imapHost: String
    let imapPort: Int
    let imapStarttls: Bool
    let smtpHost: String
    let smtpPort: Int

    /// SSL for 465, STARTTLS for 587 (matches the server's derivation).
    var smtpSecurity: String { smtpPort == 587 ? "starttls" : "ssl" }
    var hasSMTP: Bool { !smtpHost.isEmpty }

    /// App-password / OAuth banner shown when the provider is selected. The
    /// title/body are localization keys (PT base); `url` opens the provider's
    /// password page.
    struct Note: Hashable {
        let title: String
        let body: String
        let url: String
        let linkLabel: String
    }
    let note: Note?

    static let custom = EmailProvider(
        id: "", label: "Custom…", emailExample: "you@example.com",
        imapHost: "", imapPort: 993, imapStarttls: false,
        smtpHost: "", smtpPort: 465, note: nil)

    /// The eight presets from the server, in the same order as the web form.
    static let all: [EmailProvider] = [
        .init(id: "gmail", label: "Gmail", emailExample: "voce@gmail.com",
              imapHost: "imap.gmail.com", imapPort: 993, imapStarttls: false,
              smtpHost: "smtp.gmail.com", smtpPort: 465, note: .gmail),
        .init(id: "google_workspace", label: "Google Workspace / .edu", emailExample: "voce@escola.edu",
              imapHost: "imap.gmail.com", imapPort: 993, imapStarttls: false,
              smtpHost: "smtp.gmail.com", smtpPort: 587, note: .gmail),
        .init(id: "migadu", label: "Migadu", emailExample: "voce@seudominio.com",
              imapHost: "imap.migadu.com", imapPort: 993, imapStarttls: false,
              smtpHost: "smtp.migadu.com", smtpPort: 465, note: nil),
        .init(id: "icloud", label: "iCloud", emailExample: "voce@icloud.com",
              imapHost: "imap.mail.me.com", imapPort: 993, imapStarttls: false,
              smtpHost: "smtp.mail.me.com", smtpPort: 587, note: .icloud),
        .init(id: "outlook", label: "Outlook / Office 365", emailExample: "voce@outlook.com",
              imapHost: "outlook.office365.com", imapPort: 993, imapStarttls: false,
              smtpHost: "smtp.office365.com", smtpPort: 587, note: .outlook),
        .init(id: "fastmail", label: "Fastmail", emailExample: "voce@fastmail.com",
              imapHost: "imap.fastmail.com", imapPort: 993, imapStarttls: false,
              smtpHost: "smtp.fastmail.com", smtpPort: 465, note: nil),
        .init(id: "yahoo", label: "Yahoo", emailExample: "voce@yahoo.com",
              imapHost: "imap.mail.yahoo.com", imapPort: 993, imapStarttls: false,
              smtpHost: "smtp.mail.yahoo.com", smtpPort: 465, note: .yahoo),
        .init(id: "dovecot", label: "Dovecot IMAP (no SMTP)", emailExample: "voce@exemplo.com",
              imapHost: "", imapPort: 31143, imapStarttls: false,
              smtpHost: "", smtpPort: 465, note: nil),
    ]

    static func with(id: String) -> EmailProvider {
        all.first { $0.id == id } ?? custom
    }

    /// Best-effort match of the email domain to a preset, so typing the email
    /// auto-selects the provider (like picking it from the dropdown).
    static func match(email: String) -> EmailProvider? {
        let domain = email.split(separator: "@").last.map { $0.lowercased() } ?? ""
        switch domain {
        case "gmail.com", "googlemail.com":                       return with(id: "gmail")
        case "icloud.com", "me.com", "mac.com":                   return with(id: "icloud")
        case "outlook.com", "hotmail.com", "live.com", "msn.com": return with(id: "outlook")
        case "yahoo.com", "ymail.com", "rocketmail.com":          return with(id: "yahoo")
        case "fastmail.com", "fastmail.fm":                       return with(id: "fastmail")
        case "migadu.com":                                        return with(id: "migadu")
        default:                                                  return nil
        }
    }
}

extension EmailProvider.Note {
    static let gmail = Self(
        title: "O Gmail precisa de uma senha de app",
        body: "Sua senha normal do Google não funciona no IMAP. Gere uma senha de app de 16 caracteres (precisa da verificação em 2 etapas ativada) e cole no campo Senha.",
        url: "https://myaccount.google.com/apppasswords",
        linkLabel: "Gerar senha de app")
    static let icloud = Self(
        title: "O iCloud precisa de uma senha de app",
        body: "Entre no seu Apple ID, vá em Iniciar Sessão e Segurança → Senhas de App e gere uma (precisa de 2FA no Apple ID).",
        url: "https://account.apple.com/account/manage",
        linkLabel: "Gerar senha de app")
    static let yahoo = Self(
        title: "O Yahoo precisa de uma senha de app",
        body: "Gere uma senha de app na Segurança da Conta Yahoo (precisa da verificação em 2 etapas ativada) e cole no campo Senha.",
        url: "https://login.yahoo.com/account/security/app-passwords",
        linkLabel: "Gerar senha de app")
    static let outlook = Self(
        title: "Outlook / Office 365 precisa de OAuth",
        body: "A Microsoft desativa o login por senha no IMAP/SMTP na maioria das contas Outlook/Microsoft 365. O Odysseus ainda não suporta OAuth da Microsoft, então este preset é só um espaço reservado.",
        url: "https://learn.microsoft.com/exchange/clients-and-mobile-in-exchange-online/disable-basic-authentication-in-exchange-online",
        linkLabel: "Ler nota da Microsoft")
}
