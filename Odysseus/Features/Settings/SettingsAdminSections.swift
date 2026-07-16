import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

// MARK: - Models (tolerant — accounts may have none of these configured)

struct AdminUser: Decodable, Identifiable {
    var username: String
    var isAdmin: Bool
    var id: String { username }
    enum CodingKeys: String, CodingKey { case username, name, email, is_admin, admin }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        username = (try? c.decode(String.self, forKey: .username))
            ?? (try? c.decode(String.self, forKey: .name))
            ?? (try? c.decode(String.self, forKey: .email)) ?? "user"
        isAdmin = (try? c.decode(Bool.self, forKey: .is_admin)) ?? (try? c.decode(Bool.self, forKey: .admin)) ?? false
    }
}

struct Integration: Decodable, Identifiable {
    var id: String
    var name: String
    var baseURL: String?
    var authType: String?
    var enabled: Bool
    enum CodingKeys: String, CodingKey { case id, name, base_url, url, auth_type, enabled, is_enabled }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "integração"
        baseURL = (try? c.decodeIfPresent(String.self, forKey: .base_url)) ?? (try? c.decodeIfPresent(String.self, forKey: .url))
        authType = try? c.decodeIfPresent(String.self, forKey: .auth_type)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? (try? c.decode(Bool.self, forKey: .is_enabled)) ?? true
    }
}

struct MCPServer: Decodable, Identifiable {
    var id: String
    var name: String
    var status: String?
    var url: String?
    var enabled: Bool
    enum CodingKeys: String, CodingKey { case id, name, status, url, base_url, auth_url, enabled, is_enabled }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "servidor"
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? (try? c.decodeIfPresent(String.self, forKey: .base_url))
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? (try? c.decode(Bool.self, forKey: .is_enabled)) ?? true
    }
}

struct AgentTool: Decodable, Identifiable {
    var id: String
    var enabled: Bool
    enum CodingKeys: String, CodingKey { case id, name, enabled }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? (try? c.decode(String.self, forKey: .name)) ?? "tool"
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
    }
}

// MARK: - API

extension APIClient {
    func adminUsers() async throws -> [AdminUser] { decodeList(AdminUser.self, try await send(request("/api/auth/users"))) }
    /// Built-in agent tools with on/off state. `GET /api/tools` → {tools:[{id,enabled}]}.
    func agentTools() async throws -> [AgentTool] { decodeList(AgentTool.self, try await send(request("/api/tools"))) }
    /// Persists the disabled set. `POST /api/tools` with {disabled:[ids]} — tools
    /// NOT in the list are enabled (inverse-list, matches the web admin).
    func saveAgentTools(disabled: [String]) async throws {
        var req = request("/api/tools", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["disabled": disabled])
        _ = try await send(req)
    }
    /// Live diagnostic log lines. `GET /api/diagnostics/logs?limit=N` → {logs:[String]}.
    func diagnosticsLogs(limit: Int) async throws -> [String] {
        let data = try await send(request("/api/diagnostics/logs?limit=\(limit)"))
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (obj["logs"] as? [String]) ?? []
    }
    func mcpServers() async throws -> [MCPServer] { decodeList(MCPServer.self, try await send(request("/api/mcp/servers"))) }
    func reconnectMCP(_ id: String) async throws { _ = try await send(request("/api/mcp/servers/\(encPath(id))/reconnect", method: "POST")) }
    func integrations() async throws -> [Integration] { decodeList(Integration.self, try await send(request("/api/auth/integrations"))) }
    func deleteIntegration(_ id: String) async throws { _ = try await send(request("/api/auth/integrations/\(encPath(id))", method: "DELETE")) }
    func testIntegration(_ id: String) async throws { _ = try await send(request("/api/auth/integrations/\(encPath(id))/test", method: "POST")) }
    func fireReminder() async throws { _ = try await send(request("/api/notes/fire-reminder", method: "POST")) }

    // Users
    private func userPath(_ username: String) -> String {
        "/api/auth/users/\(username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username)"
    }
    func createUser(username: String, password: String, isAdmin: Bool) async throws {
        struct B: Encodable { let username: String; let password: String; let is_admin: Bool }
        _ = try await send(try jsonRequest("/api/auth/users", method: "POST",
                                           body: B(username: username, password: password, is_admin: isAdmin)))
    }
    func setUserAdmin(_ username: String, _ isAdmin: Bool) async throws {
        struct B: Encodable { let is_admin: Bool }
        _ = try await send(try jsonRequest(userPath(username), method: "PUT", body: B(is_admin: isAdmin)))
    }
    func renameUser(_ username: String, to newName: String) async throws {
        struct B: Encodable { let username: String }
        _ = try await send(try jsonRequest(userPath(username), method: "PUT", body: B(username: newName)))
    }
    func deleteUser(_ username: String) async throws { _ = try await send(request(userPath(username), method: "DELETE")) }
    func signupEnabled() async throws -> Bool {
        let data = try await send(request("/api/auth/policy"))
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (d["signup_enabled"] as? Bool) ?? false
    }
    func toggleSignup() async throws { _ = try await send(request("/api/auth/signup-toggle", method: "POST")) }

    // System
    func exportData() async throws -> Data { try await send(request("/api/export")) }
    func wipeCategory(_ category: String) async throws { _ = try await send(request("/api/admin/wipe/\(encPath(category))", method: "DELETE")) }

    // Integration creation (JSON body)
    func createIntegration(_ body: [String: Any]) async throws {
        var req = request("/api/auth/integrations", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await send(req)
    }
    /// `POST /api/mcp/servers` reads FastAPI `Form(...)` fields, not JSON (like
    /// `/api/model-endpoints`) — args/env travel as JSON-encoded strings in the form.
    func createMCPServer(name: String, transport: String, command: String,
                         args: String, env: String) async throws {
        _ = try await send(formRequest("/api/mcp/servers", fields: [
            "name": name, "transport": transport, "command": command,
            "args": args, "env": env,
        ]))
    }
}

// MARK: - Reminders (Lembretes)

@MainActor final class RemindersVM: ObservableObject {
    @Published var channel = "email"
    @Published var emailTo = ""
    @Published var ntfyTopic = ""
    @Published var webhookId = ""
    @Published var synthesis = false
    @Published var persona = ""
    @Published var loading = false
    @Published var note: String?
    @Published var integrations: [Integration] = []
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func load() async {
        loading = true; defer { loading = false }
        let bag = (try? await api.getSettings()) ?? SettingsBag(dict: [:])
        channel = bag.string("reminder_channel").isEmpty ? "email" : bag.string("reminder_channel")
        emailTo = bag.string("reminder_email_to")
        ntfyTopic = bag.string("reminder_ntfy_topic")
        webhookId = bag.string("reminder_webhook_integration_id")
        synthesis = bag.bool("reminder_llm_synthesis")
        persona = bag.string("reminder_llm_persona")
        integrations = (try? await api.integrations()) ?? []
    }
    func save() async {
        note = nil
        do {
            try await api.saveSettings([
                "reminder_channel": channel,
                "reminder_email_to": emailTo,
                "reminder_ntfy_topic": ntfyTopic,
                "reminder_webhook_integration_id": webhookId,
                "reminder_llm_synthesis": synthesis,
                "reminder_llm_persona": persona,
            ])
            note = "Salvo."
        } catch { note = "Falha ao salvar: \(SettingsUI.msg(error))" }
    }
    func test() async {
        note = nil
        do { try await api.fireReminder(); note = "Lembrete de teste disparado." }
        catch { note = "Falha no teste: \(SettingsUI.msg(error))" }
    }
}

struct RemindersSection: View {
    @StateObject private var vm: RemindersVM
    @Environment(\.theme) private var theme
    init(app: AppState) { _vm = StateObject(wrappedValue: RemindersVM(api: app.api)) }
    private let channels = ["browser", "email", "ntfy", "webhook", "none"]

    var body: some View {
        SettingsScroll("Lembretes", subtitle: "Como o assistente te avisa de lembretes e tarefas.") {
            SettingsCard {
                SettingsUI.menuRow("Canal", value: vm.channel, options: channels, theme: theme) { vm.channel = $0 }
                switch vm.channel {
                case "email": SettingsUI.field("Email de destino", $vm.emailTo, placeholder: "voce@exemplo.com", theme: theme)
                case "ntfy":  SettingsUI.field("Tópico ntfy", $vm.ntfyTopic, placeholder: "meu-topico", theme: theme)
                case "webhook":
                    SettingsUI.menuRow("Integração (webhook)", value: webhookName, options: ["—"] + vm.integrations.map(\.name), theme: theme) { name in
                        vm.webhookId = vm.integrations.first { $0.name == name }?.id ?? ""
                    }
                default: EmptyView()
                }
                Toggle(isOn: $vm.synthesis) {
                    Text("Resumir com IA").font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                }.tint(theme.accent)
                Text("Quando ligado, o modelo utilitário escreve um lembrete curto e acolhedor (uma linha) em vez do conteúdo cru da nota — para browser, email, ntfy e webhook.")
                    .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if vm.synthesis {
                    SettingsUI.field("Persona da IA", $vm.persona, placeholder: "ex.: assistente direto e objetivo", theme: theme)
                }
            }
            HStack {
                Button("Testar lembrete") { Task { await vm.test() } }
                    .buttonStyle(.plain).foregroundStyle(theme.fg)
                    .font(.ody(.subheadline, design: .monospaced))
                Spacer()
                if let n = vm.note { Text(n).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.green) }
                SettingsUI.saveButton(theme: theme) { Task { await vm.save() } }
            }
        }
        .task { await vm.load() }
    }
    private var webhookName: String { vm.integrations.first { $0.id == vm.webhookId }?.name ?? "—" }
}

// MARK: - Agent Tools

@MainActor final class AgentToolsVM: ObservableObject {
    @Published var maxRounds = ""
    @Published var tokenBudget = ""
    @Published var tokenHardMax = ""
    @Published var streamTimeout = ""
    @Published var emailConfirm = false
    @Published var servers: [MCPServer] = []
    @Published var tools: [AgentTool] = []
    @Published var loading = false
    @Published var note: String?
    @Published var toolsNote: String?
    @Published var savingTools = false
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func load() async {
        loading = true; defer { loading = false }
        let bag = (try? await api.getSettings()) ?? SettingsBag(dict: [:])
        maxRounds = String(bag.int("agent_max_rounds"))
        tokenBudget = String(bag.int("agent_input_token_budget"))
        tokenHardMax = String(bag.int("agent_input_token_hard_max"))
        streamTimeout = String(bag.int("agent_stream_timeout_seconds"))
        emailConfirm = bag.bool("agent_email_confirm")
        servers = (try? await api.mcpServers()) ?? []
        tools = (try? await api.agentTools()) ?? []
    }
    func toggleTool(_ id: String) {
        guard let i = tools.firstIndex(where: { $0.id == id }) else { return }
        tools[i].enabled.toggle()
    }
    func setCategory(_ ids: [String], enabled: Bool) {
        for id in ids { if let i = tools.firstIndex(where: { $0.id == id }) { tools[i].enabled = enabled } }
    }
    func saveTools() async {
        savingTools = true; toolsNote = nil; defer { savingTools = false }
        let disabled = tools.filter { !$0.enabled }.map(\.id)
        do { try await api.saveAgentTools(disabled: disabled); toolsNote = "Salvo." }
        catch { toolsNote = "Falha: \(SettingsUI.msg(error))" }
    }
    func save() async {
        note = nil
        var p: [String: Any] = ["agent_email_confirm": emailConfirm]
        for (k, v) in [("agent_max_rounds", maxRounds), ("agent_input_token_budget", tokenBudget),
                       ("agent_input_token_hard_max", tokenHardMax), ("agent_stream_timeout_seconds", streamTimeout)] {
            if let n = Int(v) { p[k] = n }
        }
        do { try await api.saveSettings(p); note = "Salvo." }
        catch { note = "Falha: \(SettingsUI.msg(error))" }
    }
    func reconnect(_ s: MCPServer) async {
        do { try await api.reconnectMCP(s.id); await load() }
        catch { note = "Falha ao reconectar: \(SettingsUI.msg(error))" }
    }
}

struct AgentToolsSection: View {
    @StateObject private var vm: AgentToolsVM
    @Environment(\.theme) private var theme
    init(app: AppState) { _vm = StateObject(wrappedValue: AgentToolsVM(api: app.api)) }

    var body: some View {
        SettingsScroll("Agent Tools", subtitle: "Limites de execução do agente e servidores MCP.") {
            SettingsCard {
                Text("Execução").font(.ody(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(theme.fg)
                SettingsUI.field("Máx. de rounds", $vm.maxRounds, placeholder: "ex.: 8", theme: theme, numeric: true)
                SettingsUI.field("Orçamento de tokens (entrada)", $vm.tokenBudget, placeholder: "ex.: 120000", theme: theme, numeric: true)
                SettingsUI.field("Teto duro de tokens", $vm.tokenHardMax, placeholder: "ex.: 200000", theme: theme, numeric: true)
                SettingsUI.field("Timeout do stream (s)", $vm.streamTimeout, placeholder: "ex.: 300", theme: theme, numeric: true)
                Toggle(isOn: $vm.emailConfirm) {
                    Text("Confirmar envio de email").font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                }.tint(theme.accent)
                HStack {
                    Spacer()
                    if let n = vm.note { Text(n).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.green) }
                    SettingsUI.saveButton(theme: theme) { Task { await vm.save() } }
                }
            }
            BuiltinToolsCard(vm: vm)
            SettingsCard {
                Text("Servidores MCP").font(.ody(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(theme.fg)
                if vm.servers.isEmpty {
                    Text("Nenhum servidor MCP conectado. Adicione pela web (Admin).")
                        .font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
                }
                ForEach(vm.servers) { s in
                    HStack(spacing: 8) {
                        Circle().fill(s.status == "connected" ? theme.green : theme.secondaryText).frame(width: 7, height: 7)
                        Text(s.name).font(.ody(size: 12, design: .monospaced)).foregroundStyle(theme.fg)
                        if let st = s.status { Text(st).font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText) }
                        Spacer()
                        Button("Reconectar") { Task { await vm.reconnect(s) } }
                            .buttonStyle(.plain).foregroundStyle(theme.accent).font(.ody(size: 11, design: .monospaced))
                    }
                }
            }
        }
        .task { await vm.load() }
    }
}

// MARK: - Built-in Tools catalog + card

/// Cosmetic client-side grouping (the API returns only {id, enabled}). Buckets the
/// live tool list so new server-side tools still appear (unmatched → "Outros").
enum BuiltinToolCatalog {
    struct Category: Identifiable { let label: String; let icon: String; let ids: [String]; var id: String { label } }
    static let categories: [Category] = [
        .init(label: "Código & Arquivos", icon: "chevron.left.forwardslash.chevron.right",
              ids: ["bash", "python", "glob", "grep", "read_file", "write_file", "edit_file", "ls", "get_workspace"]),
        .init(label: "Busca & Web", icon: "magnifyingglass",
              ids: ["web_search", "web_fetch", "search_chats", "search_hf_models"]),
        .init(label: "Documentos", icon: "doc.text",
              ids: ["create_document", "edit_document", "update_document", "suggest_document", "manage_documents"]),
        .init(label: "Mídia", icon: "photo",
              ids: ["generate_image", "edit_image"]),
        .init(label: "Conhecimento", icon: "brain",
              ids: ["manage_memory", "manage_notes", "manage_research", "trigger_research"]),
        .init(label: "Multi-agente", icon: "person.2",
              ids: ["chat_with_model", "send_to_session", "ask_teacher", "ask_user", "pipeline"]),
        .init(label: "Sessões", icon: "bubble.left.and.bubble.right",
              ids: ["create_session", "list_sessions", "manage_session", "update_plan"]),
        .init(label: "E-mail", icon: "envelope",
              ids: ["send_email", "bulk_email", "reply_to_email", "read_email", "list_emails",
                    "list_email_accounts", "archive_email", "delete_email", "mark_email_read"]),
        .init(label: "Calendário & Contatos", icon: "calendar",
              ids: ["manage_calendar", "manage_contact", "resolve_contact", "manage_tasks"]),
        .init(label: "Modelos & Cookbook", icon: "cpu",
              ids: ["adopt_served_model", "serve_model", "serve_preset", "stop_served_model",
                    "list_served_models", "list_serve_presets", "list_cached_models", "list_cookbook_servers",
                    "download_model", "cancel_download", "list_downloads", "list_models", "manage_endpoints"]),
        .init(label: "Sistema", icon: "gearshape.2",
              ids: ["manage_settings", "manage_tokens", "manage_webhooks", "manage_mcp",
                    "manage_bg_jobs", "manage_skills", "ui_control", "app_api", "api_call"]),
    ]
    /// Returns (label, icon, tools) honoring the live list; unmatched ids → "Outros".
    static func grouped(_ tools: [AgentTool]) -> [(Category, [AgentTool])] {
        let byID = Dictionary(tools.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var used = Set<String>()
        var out: [(Category, [AgentTool])] = []
        for cat in categories {
            let items = cat.ids.compactMap { byID[$0] }
            for t in items { used.insert(t.id) }
            if !items.isEmpty { out.append((cat, items)) }
        }
        let leftovers = tools.filter { !used.contains($0.id) }.sorted { $0.id < $1.id }
        if !leftovers.isEmpty {
            out.append((Category(label: "Outros", icon: "ellipsis.circle", ids: leftovers.map(\.id)), leftovers))
        }
        return out
    }
    /// Humanize a tool id for display: "manage_calendar" → "Manage calendar".
    static func label(_ id: String) -> String {
        let s = id.replacingOccurrences(of: "_", with: " ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

struct BuiltinToolsCard: View {
    @ObservedObject var vm: AgentToolsVM
    @Environment(\.theme) private var theme
    @State private var expanded: Set<String> = []

    var body: some View {
        SettingsCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ferramentas integradas")
                        .font(.ody(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(theme.fg)
                    Text("Habilite ou desabilite as ferramentas disponíveis ao agente.")
                        .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                }
                Spacer()
                Text("\(enabledCount)/\(vm.tools.count)")
                    .font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.accent)
            }
            if vm.tools.isEmpty {
                Text("Carregando…").font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
            }
            ForEach(BuiltinToolCatalog.grouped(vm.tools), id: \.0.id) { cat, items in
                categoryView(cat, items)
            }
            HStack {
                Spacer()
                if let n = vm.toolsNote { Text(n).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.green) }
                if vm.savingTools { ProgressView().controlSize(.small) }
                else { SettingsUI.saveButton(theme: theme) { Task { await vm.saveTools() } } }
            }
        }
    }

    private var enabledCount: Int { vm.tools.filter(\.enabled).count }

    @ViewBuilder private func categoryView(_ cat: BuiltinToolCatalog.Category, _ items: [AgentTool]) -> some View {
        let on = items.filter(\.enabled).count
        let isOpen = expanded.contains(cat.id)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isOpen { expanded.remove(cat.id) } else { expanded.insert(cat.id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: cat.icon).font(.ody(size: 12)).foregroundStyle(theme.accent).frame(width: 18)
                    Text(LocalizedStringKey(cat.label)).font(.ody(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(theme.fg)
                    Spacer()
                    Text("\(on)/\(items.count)").font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                }
                .padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                HStack(spacing: 10) {
                    Button("Ativar todas") { vm.setCategory(items.map(\.id), enabled: true) }
                        .buttonStyle(.plain).font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.accent)
                    Button("Desativar todas") { vm.setCategory(items.map(\.id), enabled: false) }
                        .buttonStyle(.plain).font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                }
                .padding(.leading, 26).padding(.bottom, 4)
                ForEach(items) { t in
                    Toggle(isOn: Binding(get: { t.enabled }, set: { _ in vm.toggleTool(t.id) })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(BuiltinToolCatalog.label(t.id))
                                .font(.ody(size: 12, design: .monospaced)).foregroundStyle(theme.fg)
                            Text(t.id).font(.ody(size: 9, design: .monospaced)).foregroundStyle(theme.secondaryText)
                        }
                    }
                    .tint(theme.accent)
                    .padding(.leading, 26).padding(.vertical, 2)
                }
            }
            Divider().background(theme.border.opacity(0.5))
        }
    }
}

// MARK: - Sistema

@MainActor final class SistemaVM: ObservableObject {
    @Published var publicURL = ""
    @Published var twoFA = false
    @Published var note: String?
    // Terminal logs
    @Published var logs: [String] = []
    @Published var logSearch = ""
    @Published var logLevel = "Todos"
    @Published var logLimit = 100
    @Published var loadingLogs = false
    @Published var logsError: String?
    let logLevels = ["Todos", "INFO", "WARNING", "ERROR"]
    private let api: APIClient
    init(api: APIClient) { self.api = api }
    func load() async {
        let bag = (try? await api.getSettings()) ?? SettingsBag(dict: [:])
        publicURL = bag.string("app_public_url")
        twoFA = (try? await api.twoFAEnabled()) ?? false
        await loadLogs()
    }
    func loadLogs() async {
        loadingLogs = true; logsError = nil; defer { loadingLogs = false }
        do { logs = try await api.diagnosticsLogs(limit: logLimit) }
        catch is CancellationError {}
        catch { logsError = SettingsUI.msg(error) }
    }
    /// Extracts the level token from a "TS - module - LEVEL - msg" line.
    static func logLevel(_ line: String) -> String {
        let parts = line.components(separatedBy: " - ")
        if parts.count >= 3 {
            let lv = parts[2].trimmingCharacters(in: .whitespaces).uppercased()
            if ["INFO", "WARNING", "ERROR", "DEBUG", "CRITICAL"].contains(lv) { return lv }
        }
        for lv in ["CRITICAL", "ERROR", "WARNING", "DEBUG", "INFO"] where line.contains(" \(lv) ") || line.contains(" \(lv) -") { return lv }
        return "INFO"
    }
    var filteredLogs: [String] {
        logs.filter { line in
            let levelOK = logLevel == "Todos" || Self.logLevel(line) == logLevel
                || (logLevel == "ERROR" && Self.logLevel(line) == "CRITICAL")
            let searchOK = logSearch.isEmpty || line.localizedCaseInsensitiveContains(logSearch)
            return levelOK && searchOK
        }
    }
    func save() async {
        note = nil
        do { try await api.saveSettings(["app_public_url": publicURL]); note = "Salvo." }
        catch { note = "Falha: \(SettingsUI.msg(error))" }
    }
    func export() async {
        note = nil
        do {
            let data = try await api.exportData()
            SettingsUI.saveJSON(data, suggested: "odysseus-backup.json")
            note = "Backup exportado."
        } catch { note = "Falha ao exportar: \(SettingsUI.msg(error))" }
    }
    func wipe(_ cat: String) async {
        note = nil
        do { try await api.wipeCategory(cat); note = "Apagado: \(cat)." }
        catch { note = "Falha: \(SettingsUI.msg(error))" }
    }
}

struct SistemaSection: View {
    @StateObject private var vm: SistemaVM
    @Environment(\.theme) private var theme
    @State private var confirming: (cat: String, label: String)?
    init(app: AppState) { _vm = StateObject(wrappedValue: SistemaVM(api: app.api)) }

    private let dangers: [(cat: String, label: String, desc: String)] = [
        ("chats", "Apagar todos os chats", "Sessões, mensagens e histórico. Documentos/notas ficam."),
        ("memory", "Apagar toda a memória", "Limpa memory.json, tabela Memory e vetores. Skills não afetadas."),
        ("skills", "Apagar todas as skills", "Remove data/skills/ (todos os SKILL.md)."),
        ("notes", "Apagar todas as notas", "Toda nota, todo e checklist."),
        ("tasks", "Apagar todas as tasks", "Toda task agendada e histórico de execução."),
        ("documents", "Apagar todos os documentos", "Todo documento e versão. Drafts, exports, library."),
        ("gallery", "Apagar toda a galeria", "Todo registro de imagem e o diretório de upload."),
        ("calendar", "Apagar todo o calendário", "Todo evento e calendário (incl. CalDAV)."),
        ("all", "Apagar TUDO", "Todas as 8 categorias acima, de uma vez."),
    ]

    var body: some View {
        SettingsScroll("Sistema", subtitle: "Configurações gerais, backup e zona de perigo.") {
            if let n = vm.note { Text(n).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.green) }
            SettingsCard {
                SettingsUI.field("URL pública do app", $vm.publicURL, placeholder: "https://odysseus.exemplo.com", theme: theme)
                HStack {
                    Text("2FA").font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                    Spacer()
                    Text(vm.twoFA ? "ativo" : "inativo")
                        .font(.ody(size: 11, design: .monospaced)).foregroundStyle(vm.twoFA ? theme.green : theme.secondaryText)
                    SettingsUI.saveButton(theme: theme) { Task { await vm.save() } }
                }
            }
            SettingsCard {
                Text("Backup de dados").font(.ody(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(theme.fg)
                Text("Exporte memórias, presets, settings, skills e preferências como JSON.")
                    .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                Button { Task { await vm.export() } } label: {
                    Label("Exportar dados", systemImage: "square.and.arrow.up")
                        .font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                }.buttonStyle(.plain)
            }
            TerminalLogsCard(vm: vm)
            SettingsCard {
                Text("⚠️ Zona de perigo").font(.ody(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(Color(hex: "e05a4a"))
                Text("Irreversível. Cada item apaga uma categoria.")
                    .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                ForEach(dangers, id: \.cat) { d in
                    Rectangle().fill(theme.border).frame(height: 1)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.label).font(.ody(size: 12, design: .monospaced)).foregroundStyle(theme.fg)
                            Text(d.desc).font(.ody(size: 9, design: .monospaced)).foregroundStyle(theme.secondaryText).lineLimit(2)
                        }
                        Spacer()
                        Button("Apagar", role: .destructive) { confirming = (d.cat, d.label) }
                            .buttonStyle(.plain).foregroundStyle(Color(hex: "e05a4a")).font(.ody(size: 12, design: .monospaced))
                    }
                }
            }
        }
        .task { await vm.load() }
        .alert(confirming?.label ?? "", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Apagar", role: .destructive) { if let c = confirming { Task { await vm.wipe(c.cat) } }; confirming = nil }
            Button("Cancelar", role: .cancel) { confirming = nil }
        } message: { Text("Isso é irreversível. Confirma?") }
    }
}

struct TerminalLogsCard: View {
    @ObservedObject var vm: SistemaVM
    @Environment(\.theme) private var theme

    private func color(_ level: String) -> Color {
        switch level {
        case "ERROR", "CRITICAL": return Color(hex: "e05a4a")
        case "WARNING": return Color(hex: "e0a33a")
        case "DEBUG": return theme.secondaryText.opacity(0.7)
        default: return theme.secondaryText
        }
    }

    var body: some View {
        SettingsCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Logs do sistema")
                        .font(.ody(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(theme.fg)
                    Text("Diagnóstico ao vivo do processo Odysseus.")
                        .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                }
                Spacer()
                Button { Task { await vm.loadLogs() } } label: {
                    if vm.loadingLogs { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise").font(.ody(size: 12)).foregroundStyle(theme.accent) }
                }.buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                    TextField("Buscar nos logs…", text: $vm.logSearch)
                        .textFieldStyle(.plain).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.fg)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                Menu {
                    ForEach(vm.logLevels, id: \.self) { lv in Button(lv) { vm.logLevel = lv } }
                } label: { menuChip(vm.logLevel) }
                Menu {
                    ForEach([50, 100, 200, 500], id: \.self) { n in
                        Button("\(n) linhas") { vm.logLimit = n; Task { await vm.loadLogs() } }
                    }
                } label: { menuChip("\(vm.logLimit) linhas") }
            }
            if let e = vm.logsError {
                Text("Falha ao carregar logs: \(e)").font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.accent)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(vm.filteredLogs.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.ody(size: 9, design: .monospaced))
                            .foregroundStyle(color(SistemaVM.logLevel(line)))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if vm.filteredLogs.isEmpty && !vm.loadingLogs {
                        Text(vm.logs.isEmpty ? "Sem logs." : "Nenhuma linha corresponde ao filtro.")
                            .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                    }
                }
                .padding(8)
            }
            .frame(height: 300)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
            Text("\(vm.filteredLogs.count) de \(vm.logs.count) linhas")
                .font(.ody(size: 9, design: .monospaced)).foregroundStyle(theme.secondaryText)
        }
    }

    @ViewBuilder private func menuChip(_ label: String) -> some View {
        HStack(spacing: 4) {
            Text(LocalizedStringKey(label)).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.fg)
            Image(systemName: "chevron.up.chevron.down").font(.ody(size: 8)).foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
}

// MARK: - Usuários

@MainActor final class UsuariosVM: ObservableObject {
    @Published var users: [AdminUser] = []
    @Published var loading = false
    @Published var signupOn = false
    @Published var note: String?
    // add-user form
    @Published var newUser = ""
    @Published var newPass = ""
    @Published var newAdmin = false
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func load() async {
        loading = true; defer { loading = false }
        users = (try? await api.adminUsers()) ?? []
        signupOn = (try? await api.signupEnabled()) ?? false
    }
    func toggleSignup() async {
        do { try await api.toggleSignup(); signupOn = (try? await api.signupEnabled()) ?? signupOn }
        catch { note = "Falha: \(SettingsUI.msg(error))" }
    }
    func setAdmin(_ u: AdminUser, _ admin: Bool) async {
        do { try await api.setUserAdmin(u.username, admin); await load() }
        catch { note = "Falha: \(SettingsUI.msg(error))" }
    }
    func remove(_ u: AdminUser) async {
        do { try await api.deleteUser(u.username); await load() }
        catch { note = "Falha: \(SettingsUI.msg(error))" }
    }
    func rename(_ u: AdminUser, to name: String) async {
        do { try await api.renameUser(u.username, to: name); await load() }
        catch { note = "Falha: \(SettingsUI.msg(error))" }
    }
    func add() async {
        guard !newUser.isEmpty, newPass.count >= 8 else { note = "Usuário e senha (mín. 8) obrigatórios."; return }
        do {
            try await api.createUser(username: newUser, password: newPass, isAdmin: newAdmin)
            newUser = ""; newPass = ""; newAdmin = false; note = "Usuário criado."; await load()
        } catch { note = "Falha ao criar: \(SettingsUI.msg(error))" }
    }
}

struct UsuariosSection: View {
    @StateObject private var vm: UsuariosVM
    @Environment(\.theme) private var theme
    @State private var renaming: AdminUser?
    @State private var renameText = ""
    init(app: AppState) { _vm = StateObject(wrappedValue: UsuariosVM(api: app.api)) }

    var body: some View {
        SettingsScroll("Usuários", subtitle: "Contas com acesso a este servidor.") {
            if let n = vm.note { Text(n).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.accent) }
            SettingsCard {
                Toggle(isOn: Binding(get: { vm.signupOn }, set: { _ in Task { await vm.toggleSignup() } })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Cadastro aberto").font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                        Text("Qualquer um pode criar conta pela tela de login.")
                            .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                    }
                }.tint(theme.accent)
            }
            ForEach(vm.users) { u in
                SettingsCard {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle").foregroundStyle(theme.accent)
                        Text(u.username).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                        if u.isAdmin {
                            Text("ADMIN").font(.ody(size: 9, design: .monospaced)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1).background(theme.accent, in: Capsule())
                        }
                        Spacer()
                    }
                    HStack(spacing: 14) {
                        Button(u.isAdmin ? "Revogar admin" : "Tornar admin") { Task { await vm.setAdmin(u, !u.isAdmin) } }
                            .buttonStyle(.plain).foregroundStyle(theme.fg)
                        Button("Renomear") { renaming = u; renameText = u.username }
                            .buttonStyle(.plain).foregroundStyle(theme.fg)
                        Spacer()
                        Button("Remover", role: .destructive) { Task { await vm.remove(u) } }
                            .buttonStyle(.plain).foregroundStyle(theme.accent)
                    }
                    .font(.ody(size: 12, design: .monospaced))
                }
            }
            SettingsCard {
                Text("Adicionar usuário").font(.ody(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(theme.fg)
                SettingsUI.field("Usuário", $vm.newUser, placeholder: "nome", theme: theme)
                SettingsUI.field("Senha (mín. 8)", $vm.newPass, placeholder: "••••••••", theme: theme, secure: true)
                HStack {
                    Toggle(isOn: $vm.newAdmin) {
                        Text("Admin").font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                    }.tint(theme.accent).fixedSize()
                    Spacer()
                    SettingsUI.saveButton(theme: theme, label: "Criar") { Task { await vm.add() } }
                }
            }
        }
        .task { await vm.load() }
        .alert("Renomear usuário", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Novo nome", text: $renameText)
            Button("Salvar") { if let u = renaming { Task { await vm.rename(u, to: renameText) } }; renaming = nil }
            Button("Cancelar", role: .cancel) { renaming = nil }
        }
    }
}

// MARK: - Integrações

@MainActor final class IntegracoesVM: ObservableObject {
    @Published var items: [Integration] = []
    @Published var loading = false
    @Published var note: String?
    private let api: APIClient
    init(api: APIClient) { self.api = api }
    func load() async { loading = true; defer { loading = false }; items = (try? await api.integrations()) ?? [] }
    func test(_ i: Integration) async {
        do { try await api.testIntegration(i.id); note = "Teste enviado para \(i.name)." }
        catch { note = "Falha no teste: \(SettingsUI.msg(error))" }
    }
    func remove(_ i: Integration) async {
        do { try await api.deleteIntegration(i.id); await load() }
        catch { note = "Falha ao remover: \(SettingsUI.msg(error))" }
    }
}

struct IntegracoesSection: View {
    @StateObject private var vm: IntegracoesVM
    @Environment(\.theme) private var theme
    let app: AppState
    @State private var addKind: IntegrationKind?
    @State private var showEmail = false
    @State private var emailVM: EmailAccountsViewModel
    init(app: AppState) {
        self.app = app
        _vm = StateObject(wrappedValue: IntegracoesVM(api: app.api))
        _emailVM = State(initialValue: EmailAccountsViewModel(api: app.api))
    }
    var body: some View {
        SettingsScroll("Integrações", subtitle: "Conexões com serviços externos em um só lugar.") {
            Menu {
                Button { showEmail = true } label: { Label("Email (IMAP/SMTP)", systemImage: "envelope") }
                ForEach(IntegrationKind.allCases) { k in
                    Button { addKind = k } label: { Label(k.label, systemImage: k.icon) }
                }
            } label: {
                Label("Adicionar integração", systemImage: "plus")
                    .font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.accent)
            }
            .menuStyle(.borderlessButton)

            if vm.loading && vm.items.isEmpty { ProgressView().tint(theme.accent) }
            if let n = vm.note { Text(n).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.green) }
            if vm.items.isEmpty && !vm.loading {
                Text("Nenhuma integração ainda — use “Adicionar integração” acima.")
                    .font(.ody(size: 12, design: .monospaced)).foregroundStyle(theme.secondaryText)
            }
            ForEach(vm.items) { i in
                SettingsCard {
                    HStack(spacing: 8) {
                        Circle().fill(i.enabled ? theme.green : theme.secondaryText).frame(width: 7, height: 7)
                        Text(i.name).font(.ody(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(theme.fg)
                        Spacer()
                        if let t = i.authType { Text(t).font(.ody(size: 9, design: .monospaced)).foregroundStyle(theme.secondaryText) }
                    }
                    if let u = i.baseURL, !u.isEmpty {
                        Text(u).font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText).lineLimit(1)
                    }
                    HStack {
                        Button("Testar") { Task { await vm.test(i) } }.buttonStyle(.plain).foregroundStyle(theme.fg)
                        Spacer()
                        Button("Remover", role: .destructive) { Task { await vm.remove(i) } }
                            .buttonStyle(.plain).foregroundStyle(theme.accent)
                    }
                    .font(.ody(size: 12, design: .monospaced))
                }
            }
        }
        .task { await vm.load() }
        .sheet(item: $addKind) { kind in
            AddIntegrationView(app: app, kind: kind) { Task { await vm.load() } }
                .environment(\.theme, theme)
        }
        .sheet(isPresented: $showEmail) {
            AddEmailAccountView { payload in await emailVM.add(payload) }
                .environment(\.theme, theme)
        }
    }
}

// MARK: - Shared small UI helpers

enum SettingsUI {
    static func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? e.localizedDescription }

    /// Saves data to a user-chosen file (macOS save panel). No-op stub on iOS.
    static func saveJSON(_ data: Data, suggested: String) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url { try? data.write(to: url) }
        #else
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suggested)
        try? data.write(to: url)
        #endif
    }

    @ViewBuilder
    static func field(_ label: String, _ bind: Binding<String>, placeholder: String, theme: Theme,
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

    @ViewBuilder
    static func menuRow(_ label: String, value: String, options: [String], theme: Theme, _ pick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(label)).font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
            Menu {
                ForEach(options, id: \.self) { o in Button(o) { pick(o) } }
            } label: {
                HStack {
                    Text(value).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.ody(size: 9)).foregroundStyle(theme.secondaryText)
                }
                .padding(9).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
            }
        }
    }

    static func saveButton(theme: Theme, label: String = "Salvar", _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(label)).font(.ody(.subheadline, design: .monospaced, weight: .semibold))
                .padding(.horizontal, 16).padding(.vertical, 8).foregroundStyle(.white)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
