import SwiftUI

/// The add / edit sheet for one integration.
///
/// Each kind goes where the server keeps it: CalDAV accounts under
/// `/api/calendar/config` (per user, tested with a real PROPFIND before the
/// save), the single CardDAV account under `/api/contacts/config`, API
/// services under `/api/auth/integrations` (with the web's presets and all
/// four auth types), agents as API tokens under `/api/tokens`, MCP servers
/// as form posts. 1.8 posted the first two AND the agents to the generic
/// integrations route: the calendar never saw the accounts, the passwords
/// sat in plaintext, and the agents 400'd for a missing base_url.
enum IntegrationKind: String, CaseIterable, Identifiable {
    case caldav, carddav, api, claude, codex, mcp
    var id: String { rawValue }
    var label: String {
        switch self {
        case .caldav: return "CalDAV (Calendário)"
        case .carddav: return "Contatos (CardDAV)"
        case .api: return "API Service"
        case .claude: return "Claude Agent"
        case .codex: return "Codex Agent"
        case .mcp: return "MCP Tool Server"
        }
    }
    var icon: String {
        switch self {
        case .caldav: return "calendar"
        case .carddav: return "person.crop.circle"
        case .api: return "link"
        case .claude, .codex: return "cpu"
        case .mcp: return "square.stack.3d.up"
        }
    }
    /// Everything but a personal CalDAV account is an admin route (403 otherwise).
    var adminOnly: Bool { self != .caldav }
}

@MainActor final class AddIntegrationVM: ObservableObject {
    @Published var kind: IntegrationKind
    /// Set when the sheet edits an existing API integration (PUT instead of POST).
    let editing: Integration?
    // shared/per-type fields
    @Published var name = ""
    @Published var url = ""
    @Published var username = ""
    @Published var password = ""
    @Published var baseURL = ""
    @Published var authType = "bearer"
    @Published var authHeader = "Authorization"
    @Published var apiKey = ""
    @Published var presetKey = ""
    @Published var presets: [IntegrationPreset] = []
    @Published var command = "npx"
    @Published var args = "[\"-y\", \"@modelcontextprotocol/server-filesystem\"]"
    @Published var env = "{}"
    @Published var saving = false
    @Published var error: String?
    /// The one-time reveal of an agent token. The sheet must not dismiss
    /// while this is on screen — it is the only copy there will ever be.
    @Published var createdToken: String?
    /// Agent tokens: what the agent may do, from the server's scope list.
    /// `chat` alone was the 1.9 default; now it is only the starting point.
    @Published var scopes: Set<String> = ["chat"]
    @Published var allowedScopes: [String] = []

    /// ids the server honours (`src/integrations.py` executor) with labels
    /// the catalogue can translate — the raw ids never reach the screen.
    static let authTypes: [(id: String, label: String)] = [
        ("bearer", "Bearer"), ("header", "Cabeçalho personalizado"), ("basic", "Básico (usuário:senha)"), ("none", "Sem autenticação"),
    ]
    private let api: APIClient
    init(api: APIClient, kind: IntegrationKind, editing: Integration? = nil) {
        self.api = api; self.kind = kind; self.editing = editing
        if let e = editing {
            name = e.name; baseURL = e.baseURL ?? ""; authType = e.authType ?? "none"
            authHeader = e.authHeader ?? "Authorization"; presetKey = e.preset ?? ""
        }
    }

    func loadPresets() async {
        switch kind {
        case .api:
            guard presets.isEmpty else { return }
            presets = (try? await api.integrationPresets()) ?? []
        case .claude, .codex:
            guard allowedScopes.isEmpty else { return }
            let s = (try? await api.apiTokenScopes()) ?? []
            allowedScopes = s.isEmpty ? TokensVM.fallbackScopes : s
        default: break
        }
    }

    func applyPreset(_ key: String) {
        presetKey = key
        guard let p = presets.first(where: { $0.id == key }) else { return }
        if name.isEmpty || presets.contains(where: { $0.name == name }) { name = p.name }
        authType = p.authType
        if !p.authHeader.isEmpty { authHeader = p.authHeader }
    }

    func save() async -> Bool {
        saving = true; error = nil; defer { saving = false }
        do {
            switch kind {
            case .caldav:
                guard !password.isEmpty else { error = "Senha é obrigatória."; return false }
                // Nothing is saved until the server has actually reached the host.
                let t = try await api.testCalDAV(url: url, username: username, password: password)
                guard t.ok else { error = t.error.isEmpty ? L("Falha na conexão — nada foi salvo.") : t.error; return false }
                try await api.createCalDAVAccount(label: name.isEmpty ? "CalDAV" : name, url: url,
                                                  username: username, password: password)
            case .carddav:
                try await api.saveCardDAV(url: url, username: username, password: password)
            case .api:
                guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Nome é obrigatório."; return false }
                guard !baseURL.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Base URL é obrigatória."; return false }
                var b: [String: Any] = ["name": name, "base_url": baseURL, "auth_type": authType]
                if authType == "header" { b["auth_header"] = authHeader }
                if !presetKey.isEmpty { b["preset"] = presetKey }
                // The list hands the key back masked ("abcd****"); it is never
                // put in the field and never resent. Blank on PUT = keep it.
                if !apiKey.isEmpty { b["api_key"] = apiKey }
                if let e = editing { try await api.updateIntegration(e.id, b) }
                else { try await api.createIntegration(b) }
            case .claude, .codex:
                // The web classifies agent tokens by this exact name prefix.
                let base = kind == .claude ? "Claude Agent" : "Codex Agent"
                let n = name.trimmingCharacters(in: .whitespaces)
                let full = n.isEmpty || n.lowercased().hasPrefix(base.lowercased()) ? (n.isEmpty ? base : n) : "\(base) — \(n)"
                createdToken = try await api.createApiToken(name: full, scopes: scopes.isEmpty ? ["chat"] : Array(scopes).sorted())
                return false   // stays open: the token is shown once
            case .mcp:
                // The server json.loads these strings (silently defaulting to []/{});
                // reject bad JSON here so typos don't save a broken server config.
                let argsText = args.trimmingCharacters(in: .whitespacesAndNewlines)
                let envText = env.trimmingCharacters(in: .whitespacesAndNewlines)
                guard (try? JSONSerialization.jsonObject(with: Data(argsText.utf8))) is [Any] else {
                    self.error = "Args precisa ser um array JSON válido, ex.: [\"-y\", \"pacote\"]"
                    return false
                }
                guard (try? JSONSerialization.jsonObject(with: Data(envText.utf8))) is [String: Any] else {
                    self.error = "Env precisa ser um objeto JSON válido, ex.: {\"KEY\": \"value\"}"
                    return false
                }
                try await api.createMCPServer(name: name, transport: "stdio",
                                              command: command, args: argsText, env: envText)
            }
            return true
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}

struct AddIntegrationView: View {
    @StateObject private var vm: AddIntegrationVM
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    var onDone: () -> Void
    init(app: AppState, kind: IntegrationKind, editing: Integration? = nil, onDone: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: AddIntegrationVM(api: app.api, kind: kind, editing: editing))
        self.onDone = onDone
    }

    private var isEditing: Bool { vm.editing != nil }
    private var isAgent: Bool { vm.kind == .claude || vm.kind == .codex }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let token = vm.createdToken {
                        tokenReveal(token)
                    } else {
                        if !isEditing {
                            SettingsUI.menuRow("Tipo", value: vm.kind.label,
                                               options: IntegrationKind.allCases.map { (id: $0.rawValue, label: $0.label) },
                                               theme: theme) { picked in
                                if let k = IntegrationKind(rawValue: picked) { vm.kind = k; Task { await vm.loadPresets() } }
                            }
                        }
                        group { fields }
                        if let e = vm.error {
                            Text(LocalizedStringKey(e)).font(.ody(size: 11)).foregroundStyle(theme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
            }
            .background(theme.bg)
            .navigationTitle(isEditing ? "Editar integração" : "Adicionar integração")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if vm.createdToken == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.saving { ProgressView().controlSize(.small) }
                    else if vm.createdToken != nil { Button("Concluído") { onDone(); dismiss() } }
                    else {
                        Button(isAgent ? "Criar token" : "Salvar") {
                            Task { if await vm.save() { onDone(); dismiss() } }
                        }
                    }
                }
            }
        }
        .tint(theme.accent)
        .task { await vm.loadPresets() }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }

    @ViewBuilder private var fields: some View {
        switch vm.kind {
        case .caldav:
            f("Rótulo", $vm.name, "ex.: Trabalho")
            f("URL do servidor", $vm.url, "https://.../calendar/dav/.../user/")
            f("Usuário", $vm.username, "voce@exemplo.com")
            f("Senha", $vm.password, "•••", secure: true)
            Text("A conexão é testada antes de salvar.").font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
        case .carddav:
            Text("Uma conta CardDAV por servidor — salvar substitui a atual.")
                .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            f("URL", $vm.url, "http://localhost:5232/user/contacts/")
            f("Usuário", $vm.username, "")
            f("Senha", $vm.password, "•••", secure: true)
        case .api:
            if !vm.presets.isEmpty {
                SettingsUI.menuRow("Preset", value: vm.presets.first { $0.id == vm.presetKey }?.name ?? L("Personalizado"),
                                   options: [(id: "", label: "Personalizado")] + vm.presets.map { (id: $0.id, label: $0.name) },
                                   theme: theme) { vm.applyPreset($0) }
            }
            f("Nome", $vm.name, "My Service")
            f("Base URL", $vm.baseURL, "http://localhost:8080")
            SettingsUI.menuRow("Autenticação", value: AddIntegrationVM.authTypes.first { $0.id == vm.authType }?.label ?? vm.authType,
                               options: AddIntegrationVM.authTypes, theme: theme) { vm.authType = $0 }
            if vm.authType == "header" { f("Cabeçalho", $vm.authHeader, "X-Auth-Token") }
            if vm.authType != "none" {
                f(vm.authType == "basic" ? "Usuário e senha" : "API key", $vm.apiKey,
                  vm.authType == "basic" ? "usuario:senha" : "token/key", secure: true)
                if isEditing {
                    Text("Deixe em branco para manter a chave atual.").font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                }
            }
        case .claude, .codex:
            Text("Um token de API para o agente. Ele aparece uma única vez, depois de criado.")
                .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            f("Nome", $vm.name, vm.kind == .claude ? "Claude Agent — laptop" : "Codex Agent — laptop")
            Text("Escopos").font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
            FlowChips(items: vm.allowedScopes, selected: $vm.scopes, theme: theme)
            Text("Depois, nome e escopos podem ser editados em Tokens de API.")
                .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        case .mcp:
            f("Nome", $vm.name, "Server name")
            f("Command", $vm.command, "npx")
            f("Args (JSON)", $vm.args, "[\"-y\", \"...\"]")
            f("Env (JSON)", $vm.env, "{\"KEY\": \"value\"}")
        }
    }

    private func tokenReveal(_ token: String) -> some View {
        group {
            Label("Token criado", systemImage: "key.fill").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.green)
            Text("Copie este token agora — ele não será exibido novamente.")
                .font(.ody(size: 11)).foregroundStyle(theme.warning)
                .fixedSize(horizontal: false, vertical: true)
            Text(token).font(.ody(size: 12).monospaced()).foregroundStyle(theme.fg)
                .textSelection(.enabled)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
            Button {
                Clipboard.copy(token); copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: { Label(copied ? "Copiado" : "Copiar", systemImage: copied ? "checkmark" : "doc.on.doc") }
            .buttonStyle(.plain).font(.ody(size: 12)).foregroundStyle(theme.accent)
        }
    }

    private func group<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))
    }
    @ViewBuilder private func f(_ label: String, _ bind: Binding<String>, _ ph: String, secure: Bool = false) -> some View {
        SettingsUI.field(label, bind, placeholder: ph, theme: theme, secure: secure)
    }
}
