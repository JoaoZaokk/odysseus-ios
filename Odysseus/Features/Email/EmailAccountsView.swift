import SwiftUI

@MainActor
final class EmailAccountsViewModel: ObservableObject {
    @Published var accounts: [EmailAccount] = []
    @Published var loading = false
    @Published var saving = false
    @Published var error: String?

    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func load() async {
        loading = true; defer { loading = false }
        do { accounts = try await api.emailAccounts(); error = nil }
        catch is CancellationError {}
        catch { self.error = msg(error) }
    }

    func add(_ payload: EmailAccountPayload) async -> Bool {
        saving = true; defer { saving = false }
        do { try await api.addEmailAccount(payload); await load(); return true }
        catch { self.error = msg(error); return false }
    }

    func delete(_ acc: EmailAccount) async {
        do { try await api.deleteEmailAccount(acc.id); accounts.removeAll { $0.id == acc.id } }
        catch { self.error = msg(error) }
    }

    func makeDefault(_ acc: EmailAccount) async {
        do { try await api.setDefaultEmailAccount(acc.id); await load() }
        catch { self.error = msg(error) }
    }

    private func msg(_ e: Error) -> String {
        (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
    }
}

struct EmailAccountsView: View {
    @StateObject private var vm: EmailAccountsViewModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var toDelete: EmailAccount?
    /// Called when accounts change so the inbox can reload.
    var onChange: () -> Void = {}

    init(app: AppState, onChange: @escaping () -> Void = {}) {
        _vm = StateObject(wrappedValue: EmailAccountsViewModel(api: app.api))
        self.onChange = onChange
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    #if os(macOS)
                    // macOS sheets push toolbar buttons to a BOTTOM bar (that's why
                    // "+" ended up next to "Fechar"). Use a real top header instead:
                    // title left, "+" at the top-right.
                    macHeader
                    Rectangle().fill(theme.border).frame(height: 1)
                    #endif
                    ZStack { content }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            #if !os(macOS)
            .navigationTitle("Contas de email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            #endif
            .task { await vm.load() }
            .alert("Remover conta?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
                Button("Remover", role: .destructive) {
                    if let a = toDelete { Task { await vm.delete(a); onChange() } }; toDelete = nil
                }
                Button("Cancelar", role: .cancel) { toDelete = nil }
            } message: {
                Text(toDelete.map { $0.name.isEmpty ? $0.fromAddress : $0.name } ?? "")
            }
            #if os(macOS)
            // Push (not a nested sheet — that fails to present on macOS).
            .navigationDestination(isPresented: $showAdd) {
                AddEmailAccountView { payload in
                    let ok = await vm.add(payload)
                    if ok { onChange() }
                    return ok
                }
            }
            #else
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    AddEmailAccountView { payload in
                        let ok = await vm.add(payload)
                        if ok { onChange() }
                        return ok
                    }
                }
            }
            #endif
        }
        .tint(theme.accent)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)   // not a tiny floating box
        #endif
    }

    #if os(macOS)
    private var macHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Text("Fechar")
                    .font(.ody(.subheadline, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }.buttonStyle(.plain)
            Spacer(minLength: 8)
            Text("Contas de email")
                .font(.ody(.headline, design: .monospaced))
                .foregroundStyle(theme.fg)
            Spacer(minLength: 8)
            Button { showAdd = true } label: {
                Image(systemName: "plus")
                    .font(.ody(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(theme.accent, in: Circle())
            }.buttonStyle(.plain).help("Adicionar conta")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    #endif

    @ViewBuilder
    private var content: some View {
        if vm.accounts.isEmpty && vm.loading {
            ProgressView().tint(theme.accent)
        } else if vm.accounts.isEmpty {
            VStack(spacing: 16) {
                // The whole icon+text block is a button — the "+person" glyph adds
                // an account, just like the toolbar "+".
                Button { showAdd = true } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.ody(size: 52)).foregroundStyle(theme.accent)
                        Text("Nenhuma conta")
                            .font(.ody(.headline, design: .monospaced)).foregroundStyle(theme.fg)
                        Text("Toque em + para conectar uma conta IMAP.")
                            .font(.ody(.footnote, design: .monospaced))
                            .foregroundStyle(theme.secondaryText).multilineTextAlignment(.center)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button { showAdd = true } label: {
                    Label("Conectar conta", systemImage: "plus")
                        .font(.ody(.subheadline, design: .monospaced))
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(theme.accent, in: Capsule())
                        .foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
            .padding(40)
        } else {
            List {
                ForEach(vm.accounts) { acc in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(acc.name.isEmpty ? acc.fromAddress : acc.name)
                                    .font(.ody(.subheadline, design: .monospaced))
                                    .foregroundStyle(theme.fg)
                                if acc.isDefault {
                                    Text("padrão")
                                        .font(.ody(size: 9, design: .monospaced))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(theme.accent, in: Capsule())
                                }
                            }
                            Text(acc.subtitle)
                                .font(.ody(size: 11, design: .monospaced))
                                .foregroundStyle(theme.secondaryText).lineLimit(1)
                        }
                        Spacer()
                        // Visible actions — swipe isn't discoverable/usable on macOS.
                        if !acc.isDefault {
                            Button { Task { await vm.makeDefault(acc) } } label: {
                                Image(systemName: "star").foregroundStyle(theme.accent)
                            }.buttonStyle(.plain).help("Definir como padrão")
                        }
                        Button { toDelete = acc } label: {
                            Image(systemName: "trash").foregroundStyle(Color(hex: "e05a4a"))
                        }.buttonStyle(.plain).help("Remover conta")
                    }
                    .listRowBackground(theme.bg)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { toDelete = acc } label: { Label("Apagar", systemImage: "trash") }
                        if !acc.isDefault {
                            Button { Task { await vm.makeDefault(acc) } } label: {
                                Label("Padrão", systemImage: "star")
                            }.tint(theme.accent)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

struct AddEmailAccountView: View {
    /// Returns true on success so the sheet can close.
    let onSave: (EmailAccountPayload) async -> Bool
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var imapHost = ""
    @State private var imapPort = "993"
    @State private var imapUser = ""
    @State private var password = ""
    @State private var smtpHost = ""
    @State private var smtpPort = "587"
    @State private var sameAsImap = true
    @State private var saving = false
    @State private var error: String?
    // Last host values we auto-filled, so changing the email updates them but a
    // host the user typed by hand is never clobbered.
    @State private var autoImapHost = ""
    @State private var autoSmtpHost = ""

    private var canSave: Bool {
        !email.isEmpty && !imapHost.isEmpty && !password.isEmpty
    }

    // Plain content (no own NavigationStack): the caller provides navigation —
    // a sheet-wrapped NavigationStack on iOS, a navigationDestination push on macOS
    // (a nested sheet doesn't present on macOS).
    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    group("Conta") {
                        field("Nome (opcional)", $name, placeholder: "Trabalho")
                        field("Email", $email, placeholder: "voce@exemplo.com")
                            .onChange(of: email) { old, new in autofill(fromEmail: old, to: new) }
                    }
                    group("IMAP (entrada)") {
                        field("Servidor", $imapHost, placeholder: "imap.gmail.com")
                        HStack(alignment: .bottom, spacing: 10) {
                            field("Porta", $imapPort, placeholder: "993", numeric: true).frame(width: 110)
                            field("Usuário", $imapUser, placeholder: "voce@exemplo.com")
                        }
                        field("Senha", $password, placeholder: "•••••••", secure: true)
                    }
                    group("SMTP (envio)") {
                        Toggle(isOn: $sameAsImap) {
                            Text("SMTP igual ao IMAP").font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                        }.tint(theme.accent)
                        if !sameAsImap {
                            field("Servidor SMTP", $smtpHost, placeholder: "smtp.gmail.com")
                            field("Porta SMTP", $smtpPort, placeholder: "587", numeric: true).frame(width: 110)
                        }
                        Text("Para a maioria dos provedores, usar as credenciais do IMAP funciona. Use senha de app se tiver 2FA.")
                            .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error {
                        Text(error).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.accent)
                    }
                }
                .padding(16)
            }
            .background(theme.bg)
            .navigationTitle("Nova conta")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView().controlSize(.small) }
                    else { Button("Salvar") { save() }.disabled(!canSave) }
                }
            }
            .tint(theme.accent)
    }

    // MARK: - Themed building blocks (labels above fields — fixes the macOS
    // Form left-label overflow that made this sheet look broken).

    @ViewBuilder
    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Localize the KEY first, then uppercase the displayed text. Passing
            // `title.uppercased()` (a String, not a literal) skips localization —
            // that's why CONTA / IMAP (ENTRADA) / SMTP (ENVIO) stayed in Portuguese.
            Text(LocalizedStringKey(title))
                .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                .textCase(.uppercase)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))
    }

    @ViewBuilder
    private func field(_ label: String, _ bind: Binding<String>, placeholder: String,
                       numeric: Bool = false, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(label)).font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
            Group {
                if secure { SecureField(placeholder, text: bind) } else { TextField(placeholder, text: bind) }
            }
            .textFieldStyle(.plain).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
            .autocorrectionDisabled()
            .padding(9).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
        }
    }

    /// Mirror the email into the username and pre-fill known provider servers,
    /// without clobbering anything the user typed by hand.
    private func autofill(fromEmail old: String, to new: String) {
        // Username follows the email until the user edits it manually.
        if imapUser.isEmpty || imapUser == old { imapUser = new }
        guard let p = EmailProviderDefaults.provider(forEmail: new) else { return }
        if imapHost.isEmpty || imapHost == autoImapHost { imapHost = p.imapHost; autoImapHost = p.imapHost }
        if smtpHost.isEmpty || smtpHost == autoSmtpHost { smtpHost = p.smtpHost; autoSmtpHost = p.smtpHost }
        if imapPort.isEmpty || imapPort == "993" { imapPort = String(p.imapPort) }
        if !sameAsImap { smtpPort = String(p.smtpPort) }
    }

    private func save() {
        // Pick the right SMTP host/port/security. "Same as IMAP" no longer means
        // a hardcoded 465 — Apple needs 587/STARTTLS, so derive from the host.
        let smtp: (host: String, port: Int, security: String)
        if sameAsImap {
            smtp = EmailProviderDefaults.smtp(forImapHost: imapHost)
        } else {
            let port = Int(smtpPort) ?? 587
            smtp = (smtpHost, port, port == 465 ? "ssl" : "starttls")
        }
        let payload = EmailAccountPayload(
            name: name.isEmpty ? email : name,
            from_address: email,
            imap_host: imapHost,
            imap_port: Int(imapPort) ?? 993,
            imap_user: imapUser.isEmpty ? email : imapUser,
            imap_password: password,
            smtp_host: smtp.host,
            smtp_port: smtp.port,
            smtp_user: imapUser.isEmpty ? email : imapUser,
            smtp_password: password,
            smtp_security: smtp.security
        )
        saving = true; error = nil
        Task {
            let ok = await onSave(payload)
            saving = false
            if ok { dismiss() } else { error = "Não consegui salvar. Verifique servidor, usuário e senha." }
        }
    }
}

/// Known IMAP/SMTP defaults so the user doesn't have to memorize hostnames — and,
/// critically, so the right SMTP port is used (Apple is 587/STARTTLS, not 465/SSL;
/// only Gmail/Yahoo/AOL use 465/SSL). The generic fallback is 587/STARTTLS, which
/// is far more universal than 465.
enum EmailProviderDefaults {
    struct Provider {
        let imapHost: String
        let imapPort: Int
        let smtpHost: String
        let smtpPort: Int
        let smtpSecurity: String   // "ssl" (implicit TLS) | "starttls"
    }

    /// Match by the email domain.
    static func provider(forEmail email: String) -> Provider? {
        let domain = email.split(separator: "@").last.map { $0.lowercased() } ?? ""
        switch domain {
        case "icloud.com", "me.com", "mac.com":
            return Provider(imapHost: "imap.mail.me.com", imapPort: 993,
                            smtpHost: "smtp.mail.me.com", smtpPort: 587, smtpSecurity: "starttls")
        case "gmail.com", "googlemail.com":
            return Provider(imapHost: "imap.gmail.com", imapPort: 993,
                            smtpHost: "smtp.gmail.com", smtpPort: 465, smtpSecurity: "ssl")
        case "outlook.com", "hotmail.com", "live.com", "msn.com", "office365.com":
            return Provider(imapHost: "outlook.office365.com", imapPort: 993,
                            smtpHost: "smtp.office365.com", smtpPort: 587, smtpSecurity: "starttls")
        case "yahoo.com", "ymail.com", "rocketmail.com":
            return Provider(imapHost: "imap.mail.yahoo.com", imapPort: 993,
                            smtpHost: "smtp.mail.yahoo.com", smtpPort: 465, smtpSecurity: "ssl")
        case "aol.com":
            return Provider(imapHost: "imap.aol.com", imapPort: 993,
                            smtpHost: "smtp.aol.com", smtpPort: 465, smtpSecurity: "ssl")
        case "zoho.com":
            return Provider(imapHost: "imap.zoho.com", imapPort: 993,
                            smtpHost: "smtp.zoho.com", smtpPort: 587, smtpSecurity: "starttls")
        case "gmx.com", "gmx.net":
            return Provider(imapHost: "imap.gmx.com", imapPort: 993,
                            smtpHost: "mail.gmx.com", smtpPort: 587, smtpSecurity: "starttls")
        default:
            return nil
        }
    }

    /// SMTP settings to use when "SMTP same as IMAP" is on. Derives from the IMAP
    /// host so a known provider gets the right port even if the user typed the host
    /// by hand; otherwise host with imap→smtp and 587/STARTTLS.
    static func smtp(forImapHost host: String) -> (host: String, port: Int, security: String) {
        let h = host.lowercased()
        if h.contains("me.com") || h.contains("icloud") { return ("smtp.mail.me.com", 587, "starttls") }
        if h.contains("gmail") || h.contains("googlemail") { return ("smtp.gmail.com", 465, "ssl") }
        if h.contains("office365") || h.contains("outlook") || h.contains("hotmail") || h.contains("live.com") {
            return ("smtp.office365.com", 587, "starttls")
        }
        if h.contains("yahoo") { return ("smtp.mail.yahoo.com", 465, "ssl") }
        if h.contains("aol") { return ("smtp.aol.com", 465, "ssl") }
        if h.contains("zoho") { return ("smtp.zoho.com", 587, "starttls") }
        if h.contains("gmx") { return ("mail.gmx.com", 587, "starttls") }
        let smtpHost = host.replacingOccurrences(of: "imap", with: "smtp")
        return (smtpHost, 587, "starttls")
    }
}
