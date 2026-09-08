import SwiftUI

/// Settings › Tokens de API (admin). List, create with the server's scope
/// list, reveal once, revoke. There is no expiry and no deactivate route —
/// delete is the only revoke.
@MainActor final class TokensVM: ObservableObject {
    @Published var items: [APITokenRow] = []
    @Published var allowedScopes: [String] = []
    @Published var loading = false
    @Published var note: String?
    @Published var newName = ""
    @Published var newScopes: Set<String> = ["chat"]
    /// The one-time raw token. Cleared by the user, never by a reload.
    @Published var revealed: String?
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    static let fallbackScopes = ["chat", "todos:read", "todos:write", "documents:read", "documents:write",
                                 "email:read", "email:draft", "email:send", "calendar:read", "calendar:write",
                                 "memory:read", "memory:write", "cookbook:read", "cookbook:launch"]

    func load() async {
        loading = true; defer { loading = false }
        items = (try? await api.apiTokens()) ?? []
        let s = (try? await api.apiTokenScopes()) ?? []
        allowedScopes = s.isEmpty ? Self.fallbackScopes : s
    }

    func create() async {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { note = "Nome do token é obrigatório."; return }
        note = nil
        do {
            // The server grants "chat" when the list is empty; say so by sending it.
            let scopes = newScopes.isEmpty ? ["chat"] : Array(newScopes).sorted()
            revealed = try await api.createApiToken(name: n, scopes: scopes)
            newName = ""; newScopes = ["chat"]
            await load()
        } catch { note = SettingsUI.failure(error, "Falha ao criar: %@", admin: "Só um administrador pode criar tokens de API.") }
    }

    func revoke(_ t: APITokenRow) async {
        note = nil
        do { try await api.deleteApiToken(t.id); items.removeAll { $0.id == t.id } }
        catch { note = SettingsUI.failure(error, "Falha ao revogar: %@", admin: "Este token pertence a outra conta.") }
    }
}

struct TokensSection: View {
    @StateObject private var vm: TokensVM
    @Environment(\.theme) private var theme
    @State private var revoking: APITokenRow?
    @State private var copied = false
    init(app: AppState) { _vm = StateObject(wrappedValue: TokensVM(api: app.api)) }

    var body: some View {
        SettingsScroll("Tokens de API", subtitle: "Chaves para integrações externas falarem com este servidor.") {
            if let n = vm.note { Text(LocalizedStringKey(n)).font(.ody(size: 11)).foregroundStyle(theme.danger) }
            if let t = vm.revealed { reveal(t) }

            SettingsCard {
                Text("Criar token").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
                SettingsUI.field("Nome", $vm.newName, placeholder: "ex.: Claude Agent — laptop", theme: theme)
                Text("Escopos").font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                FlowChips(items: vm.allowedScopes, selected: $vm.newScopes, theme: theme)
                HStack { Spacer(); SettingsUI.saveButton(theme: theme, label: "Criar token") { Task { await vm.create() } } }
            }

            if vm.loading && vm.items.isEmpty { ProgressView().tint(theme.accent) }
            if vm.items.isEmpty && !vm.loading {
                Text("Nenhum token ainda.").font(.ody(size: 12)).foregroundStyle(theme.secondaryText)
            }
            ForEach(vm.items) { t in
                SettingsCard {
                    HStack(spacing: 8) {
                        Image(systemName: t.isAgent ? "cpu" : "key").foregroundStyle(theme.accent)
                        Text(t.name).font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg).lineLimit(1)
                        Spacer()
                        Text(t.tokenPrefix + "…").font(.ody(size: 10).monospaced()).foregroundStyle(theme.secondaryText)
                    }
                    Text(t.scopes.joined(separator: " · ")).font(.ody(size: 10)).foregroundStyle(theme.secondaryText).lineLimit(2)
                    HStack {
                        if let u = t.lastUsedAt, !u.isEmpty {
                            Text(L("Último uso: %@", String(u.prefix(10)))).font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                        } else {
                            Text("Nunca usado").font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                        }
                        Spacer()
                        Button("Revogar", role: .destructive) { revoking = t }
                            .buttonStyle(.plain).foregroundStyle(theme.danger).font(.ody(size: 12))
                    }
                }
            }
        }
        .task { await vm.load() }
        .alert(revoking?.name ?? "", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } })) {
            Button("Revogar", role: .destructive) { if let t = revoking { Task { await vm.revoke(t) } }; revoking = nil }
            Button("Cancelar", role: .cancel) { revoking = nil }
        } message: { Text("Integrações que usam este token perdem o acesso. Isso é irreversível.") }
    }

    private func reveal(_ token: String) -> some View {
        SettingsCard {
            Label("Token criado", systemImage: "key.fill").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.green)
            Text("Copie este token agora — ele não será exibido novamente.")
                .font(.ody(size: 11)).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true)
            Text(token).font(.ody(size: 12).monospaced()).foregroundStyle(theme.fg).textSelection(.enabled)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button {
                    Clipboard.copy(token); copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: { Label(copied ? "Copiado" : "Copiar", systemImage: copied ? "checkmark" : "doc.on.doc") }
                .buttonStyle(.plain).font(.ody(size: 12)).foregroundStyle(theme.accent)
                Spacer()
                Button("OK, guardei") { vm.revealed = nil }
                    .buttonStyle(.plain).font(.ody(size: 12)).foregroundStyle(theme.fg)
            }
        }
    }
}

/// Toggle chips that wrap. Used for scope sets and allowed-model lists.
struct FlowChips: View {
    let items: [String]
    @Binding var selected: Set<String>
    let theme: Theme

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 110), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { s in
                let on = selected.contains(s)
                Button {
                    if on { selected.remove(s) } else { selected.insert(s) }
                } label: {
                    Text(s).font(.ody(size: 11).monospaced()).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(on ? theme.accent.opacity(0.18) : theme.bg, in: Capsule())
                        .overlay(Capsule().stroke(on ? theme.accent : theme.border, lineWidth: 1))
                        .foregroundStyle(on ? theme.fg : theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
