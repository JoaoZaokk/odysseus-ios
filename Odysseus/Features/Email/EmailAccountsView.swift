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
                content
            }
            .navigationTitle("Contas de email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await vm.load() }
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
    }

    @ViewBuilder
    private var content: some View {
        if vm.accounts.isEmpty && vm.loading {
            ProgressView().tint(theme.accent)
        } else if vm.accounts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.ody(size: 44)).foregroundStyle(theme.accent)
                Text("Nenhuma conta")
                    .font(.ody(.headline, design: .monospaced)).foregroundStyle(theme.fg)
                Text("Toque em + para conectar uma conta IMAP.")
                    .font(.ody(.footnote, design: .monospaced))
                    .foregroundStyle(theme.secondaryText).multilineTextAlignment(.center)
            }
            .padding(40)
        } else {
            List {
                ForEach(vm.accounts) { acc in
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
                    .listRowBackground(theme.bg)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await vm.delete(acc); onChange() }
                        } label: { Label("Apagar", systemImage: "trash") }
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
    @State private var smtpPort = "465"
    @State private var sameAsImap = true
    @State private var saving = false
    @State private var error: String?

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
                            .onChange(of: email) { _, new in
                                if imapUser.isEmpty || imapUser == name { imapUser = new }
                            }
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
                            field("Porta SMTP", $smtpPort, placeholder: "465", numeric: true).frame(width: 110)
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
            Text(title.uppercased())
                .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
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

    private func save() {
        let payload = EmailAccountPayload(
            name: name.isEmpty ? email : name,
            from_address: email,
            imap_host: imapHost,
            imap_port: Int(imapPort) ?? 993,
            imap_user: imapUser.isEmpty ? email : imapUser,
            imap_password: password,
            smtp_host: sameAsImap ? imapHost.replacingOccurrences(of: "imap", with: "smtp") : smtpHost,
            smtp_port: sameAsImap ? 465 : (Int(smtpPort) ?? 465),
            smtp_user: imapUser.isEmpty ? email : imapUser,
            smtp_password: password,
            smtp_security: (sameAsImap ? 465 : (Int(smtpPort) ?? 465)) == 587 ? "starttls" : "ssl"
        )
        saving = true; error = nil
        Task {
            let ok = await onSave(payload)
            saving = false
            if ok { dismiss() } else { error = "Não consegui salvar. Verifique servidor, usuário e senha." }
        }
    }
}
