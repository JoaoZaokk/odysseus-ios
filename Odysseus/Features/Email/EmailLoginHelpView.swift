import SwiftUI

/// "How to connect an email account" tutorial.
///
/// The text lives in the app's `.strings` catalogues like every other string:
/// the pt-BR literal below *is* the lookup key, resolved at the render site with
/// `Text(LocalizedStringKey(_:))`. It used to carry its own five-language table
/// and a flag picker, which meant the other 39 languages read it in English and
/// the tutorial ignored the language chosen in Ajustes › Idioma.
struct EmailLoginHelpView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(LocalizedStringKey(EmailLoginGuide.title))
                        .font(.ody(.title3, design: .monospaced).weight(.semibold)).foregroundStyle(theme.fg)
                    Text(LocalizedStringKey(EmailLoginGuide.intro))
                        .font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(EmailLoginGuide.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.ody(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                                    .frame(width: 22, height: 22).background(theme.accent, in: Circle())
                                Text(LocalizedStringKey(step)).font(.ody(size: 13, design: .monospaced)).foregroundStyle(theme.fg)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey(EmailLoginGuide.serversTitle))
                            .font(.ody(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(theme.fg)
                        ForEach(EmailLoginGuide.servers, id: \.self) { s in
                            // Host names and ports: not localized on purpose.
                            Text(s).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb").foregroundStyle(theme.accent)
                        Text(LocalizedStringKey(EmailLoginGuide.tip)).font(.ody(size: 12, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
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
}

/// The tutorial's copy, as catalogue keys.
///
/// Every literal here has to match its entry in the 44 `.strings` catalogues
/// byte for byte — rewording one silently unlocalises it in 43 languages.
/// Step 4 names the **Criar** button: it said "Salvar" for a long time, which is
/// a button this screen does not have (see `EmailAccountsView.actionRow`).
enum EmailLoginGuide {
    static let title = "Como conectar seu email"
    static let intro = "Provedores com verificação em duas etapas (iCloud, Gmail, Outlook) exigem uma senha de app — não a senha normal da sua conta."
    static let steps = [
        "Gere uma senha de app no site do provedor. iCloud: account.apple.com → Iniciar Sessão e Segurança → Senhas de App → +.",
        "No Odysseus, abra Email → ícone de contas → toque em +.",
        "Preencha: Nome, seu email, servidor IMAP e porta, usuário (seu email) e a senha de app.",
        "Toque em Criar. A caixa carrega em alguns segundos.",
    ]
    static let serversTitle = "Servidores comuns"
    static let tip = "Se aparecer “timed out”, a senha provavelmente está errada — gere uma nova senha de app."

    /// Shared (technical, language-agnostic) server list.
    static let servers = [
        "iCloud — imap.mail.me.com:993 · smtp.mail.me.com:587",
        "Gmail — imap.gmail.com:993 · smtp.gmail.com:465",
        "Outlook — outlook.office365.com:993 · smtp.office365.com:587",
    ]
}
