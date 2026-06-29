import SwiftUI

/// Self-contained "how to connect an email account" tutorial in 5 languages
/// (PT / EN / ES / JA / ZH). Defaults to the device language; a picker lets the
/// user switch. Text is kept here (not the app's .strings) so it works regardless
/// of which languages the main localization currently ships.
struct EmailLoginHelpView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var lang: String = EmailLoginGuide.deviceLang

    private var guide: EmailLoginGuide { EmailLoginGuide.all[lang] ?? EmailLoginGuide.all["en"]! }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    langPicker
                    Text(guide.title)
                        .font(.ody(.title3, design: .monospaced).weight(.semibold)).foregroundStyle(theme.fg)
                    Text(guide.intro)
                        .font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(guide.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.ody(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                                    .frame(width: 22, height: 22).background(theme.accent, in: Circle())
                                Text(step).font(.ody(size: 13, design: .monospaced)).foregroundStyle(theme.fg)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(guide.serversTitle)
                            .font(.ody(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(theme.fg)
                        ForEach(EmailLoginGuide.servers, id: \.self) { s in
                            Text(s).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb").foregroundStyle(theme.accent)
                        Text(guide.tip).font(.ody(size: 12, design: .monospaced)).foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
            }
            .background(theme.bg)
            .navigationTitle("Login")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
        .tint(theme.accent)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    private var langPicker: some View {
        HStack(spacing: 6) {
            ForEach(EmailLoginGuide.order, id: \.self) { code in
                chip(code)
            }
        }
    }

    @ViewBuilder private func chip(_ code: String) -> some View {
        let on = (lang == code)
        let label = EmailLoginGuide.all[code]?.flag ?? code.uppercased()
        Button { lang = code } label: {
            Text(label)
                .font(.ody(size: 12, design: .monospaced))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(on ? theme.accent : theme.panel, in: Capsule())
                .foregroundStyle(on ? Color.white : theme.fg)
                .overlay(Capsule().stroke(theme.border, lineWidth: on ? 0 : 1))
        }.buttonStyle(.plain)
    }
}

struct EmailLoginGuide {
    let flag: String
    let title: String
    let intro: String
    let steps: [String]
    let serversTitle: String
    let tip: String

    static let order = ["pt", "en", "es", "ja", "zh"]

    /// Best match of the device language to one of the 5, else English.
    static var deviceLang: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return order.contains(code) ? code : "en"
    }

    /// Shared (technical, language-agnostic) server list.
    static let servers = [
        "iCloud — imap.mail.me.com:993 · smtp.mail.me.com:587",
        "Gmail — imap.gmail.com:993 · smtp.gmail.com:465",
        "Outlook — outlook.office365.com:993 · smtp.office365.com:587",
    ]

    static let all: [String: EmailLoginGuide] = [
        "pt": .init(flag: "PT",
            title: "Como conectar seu email",
            intro: "Provedores com verificação em duas etapas (iCloud, Gmail, Outlook) exigem uma senha de app — não a senha normal da sua conta.",
            steps: [
                "Gere uma senha de app no site do provedor. iCloud: account.apple.com → Iniciar Sessão e Segurança → Senhas de App → +.",
                "No Odysseus, abra Email → ícone de contas → toque em +.",
                "Preencha: Nome, seu email, servidor IMAP e porta, usuário (seu email) e a senha de app.",
                "Toque em Salvar. A caixa carrega em alguns segundos.",
            ],
            serversTitle: "Servidores comuns",
            tip: "Se aparecer “timed out”, a senha provavelmente está errada — gere uma nova senha de app."),
        "en": .init(flag: "EN",
            title: "Connect your email",
            intro: "Providers with two-factor auth (iCloud, Gmail, Outlook) require an app-specific password — not your normal account password.",
            steps: [
                "Generate an app password on your provider’s site. iCloud: account.apple.com → Sign-In & Security → App-Specific Passwords → +.",
                "In Odysseus, open Email → the accounts icon → tap +.",
                "Fill in: Name, your email, IMAP server and port, username (your email), and the app password.",
                "Tap Save. The inbox loads in a few seconds.",
            ],
            serversTitle: "Common servers",
            tip: "If it times out, the password is usually wrong — generate a fresh app password."),
        "es": .init(flag: "ES",
            title: "Conecta tu correo",
            intro: "Los proveedores con verificación en dos pasos (iCloud, Gmail, Outlook) requieren una contraseña de aplicación — no la contraseña normal de tu cuenta.",
            steps: [
                "Genera una contraseña de aplicación en el sitio de tu proveedor. iCloud: account.apple.com → Inicio de sesión y seguridad → Contraseñas específicas → +.",
                "En Odysseus, abre Email → el icono de cuentas → toca +.",
                "Rellena: Nombre, tu correo, servidor IMAP y puerto, usuario (tu correo) y la contraseña de aplicación.",
                "Toca Guardar. La bandeja carga en unos segundos.",
            ],
            serversTitle: "Servidores comunes",
            tip: "Si da “timed out”, la contraseña suele estar mal — genera una nueva contraseña de aplicación."),
        "ja": .init(flag: "日本語",
            title: "メールを接続する",
            intro: "2要素認証のプロバイダ（iCloud、Gmail、Outlook）では、通常のパスワードではなく「アプリ用パスワード」が必要です。",
            steps: [
                "プロバイダのサイトでアプリ用パスワードを作成します。iCloud: account.apple.com →「サインインとセキュリティ」→「Appパスワード」→ +。",
                "Odysseus で メール → アカウントのアイコン → + をタップします。",
                "名前、メールアドレス、IMAPサーバーとポート、ユーザー名（メールアドレス）、アプリ用パスワードを入力します。",
                "「保存」をタップ。数秒で受信箱が読み込まれます。",
            ],
            serversTitle: "よく使うサーバー",
            tip: "「timed out」になる場合、パスワードが間違っていることが多いです。新しいアプリ用パスワードを作成してください。"),
        "zh": .init(flag: "中文",
            title: "连接你的邮箱",
            intro: "启用两步验证的服务商（iCloud、Gmail、Outlook）需要“应用专用密码”，而不是账户的常规密码。",
            steps: [
                "在服务商网站生成应用专用密码。iCloud：account.apple.com →“登录与安全”→“App 专用密码”→ +。",
                "在 Odysseus 中打开 邮件 → 账户图标 → 点按 +。",
                "填写：名称、你的邮箱、IMAP 服务器和端口、用户名（你的邮箱）以及应用专用密码。",
                "点按“保存”。收件箱会在几秒内加载。",
            ],
            serversTitle: "常用服务器",
            tip: "如果出现“timed out”，通常是密码错误——请重新生成应用专用密码。"),
    ]
}
