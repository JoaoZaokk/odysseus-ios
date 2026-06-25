import SwiftUI

// Add-integration form. Field sets per type come from the web's Add modals; the
// JSON bodies are inferred and validated in-app (FastAPI 422 detail is surfaced).
enum IntegrationKind: String, CaseIterable, Identifiable {
    case caldav, carddav, api, claude, codex, mcp
    var id: String { rawValue }
    var label: String {
        switch self {
        case .caldav: return "CalDAV (Calendário)"
        case .carddav: return "CardDAV (Contatos)"
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
}

@MainActor final class AddIntegrationVM: ObservableObject {
    @Published var kind: IntegrationKind
    // shared/per-type fields
    @Published var name = ""
    @Published var url = ""
    @Published var username = ""
    @Published var password = ""
    @Published var baseURL = ""
    @Published var authType = "bearer"
    @Published var authHeader = "Authorization"
    @Published var apiKey = ""
    @Published var command = "npx"
    @Published var args = "[\"-y\", \"@modelcontextprotocol/server-filesystem\"]"
    @Published var env = "{}"
    @Published var saving = false
    @Published var error: String?
    @Published var createdToken: String?

    let authTypes = ["bearer", "header", "none"]
    private let api: APIClient
    init(api: APIClient, kind: IntegrationKind) { self.api = api; self.kind = kind }

    func save() async -> Bool {
        saving = true; error = nil; defer { saving = false }
        do {
            switch kind {
            case .caldav:
                try await api.createIntegration(["type": "caldav", "name": name, "base_url": url,
                                                 "username": username, "password": password])
            case .carddav:
                try await api.createIntegration(["type": "carddav", "name": name.isEmpty ? "CardDAV" : name,
                                                 "base_url": url, "username": username, "password": password])
            case .api:
                var b: [String: Any] = ["type": "api", "name": name, "base_url": baseURL, "auth_type": authType]
                if authType == "header" { b["auth_header"] = authHeader }
                if !apiKey.isEmpty { b["api_key"] = apiKey }
                try await api.createIntegration(b)
            case .claude, .codex:
                try await api.createIntegration(["type": kind.rawValue, "name": name])
            case .mcp:
                let argsJSON = (try? JSONSerialization.jsonObject(with: Data(args.utf8))) ?? []
                let envJSON = (try? JSONSerialization.jsonObject(with: Data(env.utf8))) ?? [:]
                try await api.createMCPServer(["name": name, "transport": "stdio",
                                               "command": command, "args": argsJSON, "env": envJSON])
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
    var onDone: () -> Void
    init(app: AppState, kind: IntegrationKind, onDone: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: AddIntegrationVM(api: app.api, kind: kind))
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsUI.menuRow("Tipo", value: vm.kind.label,
                                       options: IntegrationKind.allCases.map(\.label), theme: theme) { picked in
                        if let k = IntegrationKind.allCases.first(where: { $0.label == picked }) { vm.kind = k }
                    }
                    group { fields }
                    if let e = vm.error {
                        Text(e).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            .background(theme.bg)
            .navigationTitle("Adicionar integração")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.saving { ProgressView().controlSize(.small) }
                    else { Button(vm.kind == .claude || vm.kind == .codex ? "Criar token" : "Salvar") {
                        Task { if await vm.save() { onDone(); dismiss() } }
                    } }
                }
            }
        }
        .tint(theme.accent)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }

    @ViewBuilder private var fields: some View {
        switch vm.kind {
        case .caldav:
            f("Label", $vm.name, "ex.: Trabalho")
            f("Server URL", $vm.url, "https://.../calendar/dav/.../user/")
            f("Usuário", $vm.username, "voce@exemplo.com")
            f("Senha", $vm.password, "•••", secure: true)
        case .carddav:
            f("Label", $vm.name, "ex.: Contatos")
            f("URL", $vm.url, "http://localhost:5232/user/contacts/")
            f("Usuário", $vm.username, "")
            f("Senha", $vm.password, "•••", secure: true)
        case .api:
            f("Nome", $vm.name, "My Service")
            f("Base URL", $vm.baseURL, "http://localhost:8080")
            SettingsUI.menuRow("Auth", value: vm.authType, options: vm.authTypes, theme: theme) { vm.authType = $0 }
            if vm.authType == "header" { f("Header", $vm.authHeader, "X-Auth-Token") }
            if vm.authType != "none" { f("API key", $vm.apiKey, "token/key", secure: true) }
        case .claude, .codex:
            Text("Dê um nome a este agente para diferenciá-lo dos outros (ex.: \"Claude Agent — laptop\").")
                .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            f("Nome", $vm.name, "Claude Agent — laptop")
        case .mcp:
            f("Nome", $vm.name, "Server name")
            f("Command", $vm.command, "npx")
            f("Args (JSON)", $vm.args, "[\"-y\", \"...\"]")
            f("Env (JSON)", $vm.env, "{\"KEY\": \"value\"}")
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
