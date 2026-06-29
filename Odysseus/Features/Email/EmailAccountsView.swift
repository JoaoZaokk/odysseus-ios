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

    /// Returns nil on success, or the failure message (which half failed).
    func test(_ payload: EmailAccountPayload) async -> String? {
        do { try await api.testEmailAccount(payload); return nil }
        catch { return msg(error) }
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
                AddEmailAccountView(onSave: { payload in
                    let ok = await vm.add(payload)
                    if ok { onChange() }
                    return ok
                }, onTest: { payload in await vm.test(payload) })
            }
            #else
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    AddEmailAccountView(onSave: { payload in
                        let ok = await vm.add(payload)
                        if ok { onChange() }
                        return ok
                    }, onTest: { payload in await vm.test(payload) })
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
    /// Returns nil on success, else the failure message. Tests without saving.
    var onTest: (EmailAccountPayload) async -> String? = { _ in nil }
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var providerID = ""          // "" = Custom
    @State private var name = ""
    @State private var email = ""                // from_address
    @State private var displayName = ""
    @State private var imapHost = ""
    @State private var imapPort = "993"
    @State private var imapUser = ""
    @State private var password = ""
    @State private var imapStarttls = false
    @State private var smtpHost = ""
    @State private var smtpPort = "465"
    @State private var smtpSecurity = "ssl"      // ssl | starttls | none
    @State private var sameAsImap = true
    @State private var smtpUser = ""
    @State private var smtpPassword = ""
    @State private var isDefault = false
    @State private var saving = false
    @State private var testing = false
    @State private var testResult: TestResult?
    @State private var error: String?

    enum TestResult: Equatable { case ok, fail(String) }

    private var canSave: Bool {
        !email.isEmpty && !imapHost.isEmpty && !password.isEmpty
    }
    private var current: EmailProvider { EmailProvider.with(id: providerID) }

    // Plain content (no own NavigationStack): the caller provides navigation —
    // a sheet-wrapped NavigationStack on iOS, a navigationDestination push on macOS
    // (a nested sheet doesn't present on macOS).
    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    providerGroup
                    accountGroup
                    imapGroup
                    smtpGroup
                    defaultGroup
                    statusRow
                    actionRow
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
            }
            .tint(theme.accent)
    }

    // MARK: - Sections

    private var providerGroup: some View {
        group("Provedor") {
            Menu {
                Button("Custom…") { applyProvider("") }
                ForEach(EmailProvider.all) { p in Button(p.label) { applyProvider(p.id) } }
            } label: {
                HStack {
                    Text(providerID.isEmpty ? "Custom…" : current.label)
                        .font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(theme.secondaryText)
                }
                .padding(9).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                .contentShape(Rectangle())
            }
            if let note = current.note { providerBanner(note) }
        }
    }

    private func providerBanner(_ note: EmailProvider.Note) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(note.title))
                .font(.ody(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(theme.fg)
            Text(LocalizedStringKey(note.body))
                .font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = URL(string: note.url) { openURL(url) }
            } label: {
                Label(LocalizedStringKey(note.linkLabel), systemImage: "arrow.up.forward.square")
                    .font(.ody(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(theme.accent, in: Capsule()).foregroundStyle(.white)
            }.buttonStyle(.plain).padding(.top, 2)
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) { Rectangle().fill(theme.accent).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var accountGroup: some View {
        group("Conta") {
            field("Nome (opcional)", $name, placeholder: "Trabalho")
            field("Email", $email, placeholder: "voce@exemplo.com")
                .onChange(of: email) { old, new in autofill(fromEmail: old, to: new) }
            field("Nome para exibição", $displayName, placeholder: "Seu Nome")
        }
    }

    private var imapGroup: some View {
        group("IMAP (entrada)") {
            field("Servidor", $imapHost, placeholder: "imap.gmail.com")
            HStack(alignment: .bottom, spacing: 10) {
                field("Porta", $imapPort, placeholder: "993", numeric: true).frame(width: 110)
                field("Usuário", $imapUser, placeholder: "voce@exemplo.com")
            }
            field("Senha", $password, placeholder: "•••••••", secure: true)
            toggleRow("STARTTLS", $imapStarttls)
        }
    }

    private var smtpGroup: some View {
        group("SMTP (envio)") {
            Text("opcional — deixe em branco para somente leitura")
                .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
            field("Servidor SMTP", $smtpHost, placeholder: "smtp.gmail.com")
            HStack(alignment: .bottom, spacing: 10) {
                field("Porta SMTP", $smtpPort, placeholder: "465", numeric: true).frame(width: 110)
                securityField
            }
            toggleRow("SMTP igual ao IMAP", $sameAsImap)
            if !sameAsImap {
                field("Usuário SMTP", $smtpUser, placeholder: "voce@exemplo.com")
                field("Senha SMTP", $smtpPassword, placeholder: "•••••••", secure: true)
            }
        }
    }

    private var defaultGroup: some View {
        group("Conta padrão") {
            toggleRow("Usar como conta padrão", $isDefault)
            Text("Usada quando nenhuma outra está selecionada.")
                .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if let error {
            Text(error).font(.ody(size: 11, design: .monospaced)).foregroundStyle(Color(hex: "e05a4a"))
        }
        switch testResult {
        case .ok:
            Label("Conexão OK", systemImage: "checkmark.circle.fill")
                .font(.ody(size: 11, design: .monospaced)).foregroundStyle(Color(hex: "50fa7b"))
        case .fail(let m):
            Label(m, systemImage: "xmark.octagon.fill")
                .font(.ody(size: 11, design: .monospaced)).foregroundStyle(Color(hex: "e05a4a"))
                .fixedSize(horizontal: false, vertical: true)
        case nil:
            EmptyView()
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { runTest() } label: {
                HStack(spacing: 6) {
                    if testing { ProgressView().controlSize(.small) }
                    else { Image(systemName: "bolt.horizontal.circle") }
                    Text("Testar conexão")
                }
                .font(.ody(.subheadline, design: .monospaced))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .overlay(Capsule().stroke(theme.border, lineWidth: 1)).foregroundStyle(theme.fg)
            }.buttonStyle(.plain).disabled(!canSave || testing)
            Spacer()
            Button { save() } label: {
                HStack(spacing: 6) {
                    if saving { ProgressView().controlSize(.small) }
                    else { Image(systemName: "checkmark") }
                    Text("Criar")
                }
                .font(.ody(.subheadline, design: .monospaced))
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(canSave ? theme.accent : theme.border, in: Capsule())
                .foregroundStyle(.white)
            }.buttonStyle(.plain).disabled(!canSave || saving)
        }
    }

    private func toggleRow(_ label: String, _ bind: Binding<Bool>) -> some View {
        Toggle(isOn: bind) {
            Text(LocalizedStringKey(label)).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
        }.tint(theme.accent)
    }

    private var securityField: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Segurança").font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
            Menu {
                Button("SSL") { smtpSecurity = "ssl" }
                Button("STARTTLS") { smtpSecurity = "starttls" }
                Button("None") { smtpSecurity = "none" }
            } label: {
                HStack {
                    Text(smtpSecurity.uppercased()).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(theme.secondaryText)
                }
                .padding(9).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                .contentShape(Rectangle())
            }
        }
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

    // MARK: - Logic

    /// Apply a provider preset (host/port/STARTTLS/security). "" = Custom: leave
    /// the fields as the user has them.
    private func applyProvider(_ id: String) {
        providerID = id
        testResult = nil
        guard !id.isEmpty else { return }
        let p = EmailProvider.with(id: id)
        if !p.imapHost.isEmpty { imapHost = p.imapHost }
        imapPort = String(p.imapPort)
        imapStarttls = p.imapStarttls
        smtpHost = p.smtpHost
        smtpPort = String(p.smtpPort)
        smtpSecurity = p.smtpSecurity
    }

    /// Mirror the email into the username, and auto-select a provider from the
    /// domain while still on Custom — without clobbering manual edits.
    private func autofill(fromEmail old: String, to new: String) {
        if imapUser.isEmpty || imapUser == old { imapUser = new }
        if providerID.isEmpty, let p = EmailProvider.match(email: new) { applyProvider(p.id) }
    }

    /// The exact field set the server's web form posts (static/js/settings.js).
    private func buildPayload() -> EmailAccountPayload {
        let user = imapUser.isEmpty ? email : imapUser
        let smtpU = sameAsImap ? user : (smtpUser.isEmpty ? user : smtpUser)
        let smtpP = sameAsImap ? password : smtpPassword
        return EmailAccountPayload(
            name: name.isEmpty ? email : name,
            from_address: email,
            display_name: displayName,
            imap_host: imapHost,
            imap_port: Int(imapPort) ?? 993,
            imap_user: user,
            imap_starttls: imapStarttls,
            smtp_host: smtpHost,
            smtp_port: Int(smtpPort) ?? 465,
            smtp_security: smtpSecurity,
            smtp_user: smtpU,
            is_default: isDefault,
            imap_password: password.isEmpty ? nil : password,
            smtp_password: smtpP.isEmpty ? nil : smtpP
        )
    }

    private func runTest() {
        testing = true; testResult = nil; error = nil
        let payload = buildPayload()
        Task {
            let msg = await onTest(payload)
            testing = false
            testResult = (msg == nil) ? .ok : .fail(msg ?? "")
        }
    }

    private func save() {
        saving = true; error = nil
        let payload = buildPayload()
        Task {
            let ok = await onSave(payload)
            saving = false
            if ok { dismiss() } else { error = "Não consegui salvar. Verifique servidor, usuário e senha." }
        }
    }
}
