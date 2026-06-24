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
            .sheet(isPresented: $showAdd) {
                AddEmailAccountView { payload in
                    let ok = await vm.add(payload)
                    if ok { onChange() }
                    return ok
                }
            }
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Conta") {
                    TextField("Nome (opcional)", text: $name)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: email) { _, new in
                            if imapUser.isEmpty || imapUser == name { imapUser = new }
                        }
                }
                Section("IMAP (entrada)") {
                    TextField("Servidor (imap.gmail.com)", text: $imapHost)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Porta", text: $imapPort).keyboardType(.numberPad)
                    TextField("Usuário", text: $imapUser)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Senha", text: $password)
                }
                Section {
                    Toggle("SMTP igual ao IMAP", isOn: $sameAsImap).tint(theme.accent)
                    if !sameAsImap {
                        TextField("Servidor SMTP (smtp.gmail.com)", text: $smtpHost)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Porta SMTP", text: $smtpPort).keyboardType(.numberPad)
                    }
                } header: { Text("SMTP (envio)") } footer: {
                    Text("Para a maioria dos provedores, usar as credenciais do IMAP funciona. Use senha de app se tiver 2FA.")
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(theme.accent)
                }
            }
            .navigationTitle("Nova conta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() }
                    else { Button("Salvar") { save() }.disabled(!canSave) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
        }
        .tint(theme.accent)
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
