import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

// MARK: - Models (tolerant — accounts may have none of these configured)

struct AdminUser: Decodable, Identifiable {
    var username: String
    var isAdmin: Bool
    /// The merged dict the row carries (`core/auth.py` list_users → get_privileges).
    var privileges: UserPrivileges
    var id: String { username }
    enum CodingKeys: String, CodingKey { case username, name, email, is_admin, admin, privileges }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        username = (try? c.decode(String.self, forKey: .username))
            ?? (try? c.decode(String.self, forKey: .name))
            ?? (try? c.decode(String.self, forKey: .email)) ?? "user"
        isAdmin = (try? c.decode(Bool.self, forKey: .is_admin)) ?? (try? c.decode(Bool.self, forKey: .admin)) ?? false
        privileges = (try? c.decode(UserPrivileges.self, forKey: .privileges)) ?? UserPrivileges()
    }
}

/// `DEFAULT_PRIVILEGES` in the server's core/auth.py, 1:1. Sent whole on Salvar
/// via `PUT /api/auth/users/{u}/privileges`; the reply echoes the merged dict.
struct UserPrivileges: Decodable, Equatable {
    var canUseAgent = true
    var canUseBrowser = true
    var canUseBash = false
    var canUseDocuments = true
    var canUseResearch = true
    var canGenerateImages = true
    var canManageMemory = true
    var maxMessagesPerDay = 0
    var allowedModels: [String] = []
    var allowedModelsRestricted = false
    var blockAllModels = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case canUseAgent = "can_use_agent", canUseBrowser = "can_use_browser", canUseBash = "can_use_bash"
        case canUseDocuments = "can_use_documents", canUseResearch = "can_use_research"
        case canGenerateImages = "can_generate_images", canManageMemory = "can_manage_memory"
        case maxMessagesPerDay = "max_messages_per_day", allowedModels = "allowed_models"
        case allowedModelsRestricted = "allowed_models_restricted", blockAllModels = "block_all_models"
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        canUseAgent = (try? c.decode(Bool.self, forKey: .canUseAgent)) ?? true
        canUseBrowser = (try? c.decode(Bool.self, forKey: .canUseBrowser)) ?? true
        canUseBash = (try? c.decode(Bool.self, forKey: .canUseBash)) ?? false
        canUseDocuments = (try? c.decode(Bool.self, forKey: .canUseDocuments)) ?? true
        canUseResearch = (try? c.decode(Bool.self, forKey: .canUseResearch)) ?? true
        canGenerateImages = (try? c.decode(Bool.self, forKey: .canGenerateImages)) ?? true
        canManageMemory = (try? c.decode(Bool.self, forKey: .canManageMemory)) ?? true
        maxMessagesPerDay = (try? c.decode(Int.self, forKey: .maxMessagesPerDay)) ?? 0
        allowedModels = (try? c.decode([String].self, forKey: .allowedModels)) ?? []
        allowedModelsRestricted = (try? c.decode(Bool.self, forKey: .allowedModelsRestricted)) ?? false
        blockAllModels = (try? c.decode(Bool.self, forKey: .blockAllModels)) ?? false
    }

    init(dict: [String: Any]) {
        if let d = try? JSONSerialization.data(withJSONObject: dict),
           let p = try? JSONDecoder().decode(UserPrivileges.self, from: d) { self = p }
    }

    var payload: [String: Any] {
        ["can_use_agent": canUseAgent, "can_use_browser": canUseBrowser, "can_use_bash": canUseBash,
         "can_use_documents": canUseDocuments, "can_use_research": canUseResearch,
         "can_generate_images": canGenerateImages, "can_manage_memory": canManageMemory,
         "max_messages_per_day": maxMessagesPerDay, "allowed_models": allowedModels,
         "allowed_models_restricted": allowedModelsRestricted, "block_all_models": blockAllModels]
    }
}

struct Integration: Decodable, Identifiable {
    var id: String
    var name: String
    var baseURL: String?
    var authType: String?
    var authHeader: String?
    var preset: String?
    var enabled: Bool
    enum CodingKeys: String, CodingKey { case id, name, base_url, url, auth_type, auth_header, preset, enabled, is_enabled }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        // A numeric id decodes too — the sibling models (Note, GalleryImage,
        // EmailAccount, ChatSession) all carry this branch. Without it the row
        // gets a client-invented UUID, and every button on it addresses nothing.
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) }
        else { id = UUID().uuidString }
        name = (try? c.decode(String.self, forKey: .name)) ?? "integração"
        baseURL = (try? c.decodeIfPresent(String.self, forKey: .base_url)) ?? (try? c.decodeIfPresent(String.self, forKey: .url))
        authType = try? c.decodeIfPresent(String.self, forKey: .auth_type)
        authHeader = try? c.decodeIfPresent(String.self, forKey: .auth_header)
        preset = try? c.decodeIfPresent(String.self, forKey: .preset)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? (try? c.decode(Bool.self, forKey: .is_enabled)) ?? true
    }
}

/// `GET /api/auth/integrations/presets` → `{presets: {key: {name, auth_type, auth_header, description}}}`.
struct IntegrationPreset: Identifiable, Equatable {
    var id: String          // the preset key the POST body carries
    var name: String
    var authType: String
    var authHeader: String
    var description: String
}

/// One per-user CalDAV account: `GET /api/calendar/config/accounts`.
struct CalDAVAccount: Decodable, Identifiable, Equatable {
    var id: String
    var label: String
    var url: String
    var username: String
    enum CodingKeys: String, CodingKey { case id, label, url, username }
    init(id: String, label: String, url: String, username: String) {
        self.id = id; self.label = label; self.url = url; self.username = username
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) }
        else { id = UUID().uuidString }
        label = (try? c.decode(String.self, forKey: .label)) ?? "CalDAV"
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
        username = (try? c.decode(String.self, forKey: .username)) ?? ""
    }
}

/// One row of `GET /api/tokens`. The raw secret is never in this payload —
/// `POST /api/tokens` is its one and only reveal.
struct APITokenRow: Decodable, Identifiable {
    var id: String
    var name: String
    var owner: String?
    var tokenPrefix: String
    var scopes: [String]
    var isActive: Bool
    var lastUsedAt: String?
    var createdAt: String?
    enum CodingKeys: String, CodingKey { case id, name, owner, token_prefix, scopes, is_active, last_used_at, created_at }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) }
        else { id = UUID().uuidString }
        name = (try? c.decode(String.self, forKey: .name)) ?? "token"
        owner = try? c.decodeIfPresent(String.self, forKey: .owner)
        tokenPrefix = (try? c.decode(String.self, forKey: .token_prefix)) ?? ""
        scopes = (try? c.decode([String].self, forKey: .scopes)) ?? []
        isActive = (try? c.decode(Bool.self, forKey: .is_active)) ?? true
        lastUsedAt = try? c.decodeIfPresent(String.self, forKey: .last_used_at)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .created_at)
    }
    /// The web classifies agent tokens by this name prefix and nothing else.
    var isAgent: Bool { let n = name.lowercased(); return n.hasPrefix("claude agent") || n.hasPrefix("codex agent") }
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
        // A numeric id decodes too — the sibling models (Note, GalleryImage,
        // EmailAccount, ChatSession) all carry this branch. Without it the row
        // gets a client-invented UUID, and every button on it addresses nothing.
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) }
        else { id = UUID().uuidString }
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
    /// Always HTTP 200 on a reachable server: the verdict is in the body.
    /// 1.8 discarded it and reported every failed test as sent.
    func testIntegration(_ id: String) async throws -> (ok: Bool, message: String) {
        let data = try await send(request("/api/auth/integrations/\(encPath(id))/test", method: "POST"))
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((d["ok"] as? Bool) ?? false, (d["message"] as? String) ?? "")
    }
    /// Merge-patch: only the keys sent are written. Never resend `api_key`
    /// unless the user typed one — a blank keeps the stored secret.
    func updateIntegration(_ id: String, _ body: [String: Any]) async throws {
        var req = request("/api/auth/integrations/\(encPath(id))", method: "PUT")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await send(req)
    }
    func integrationPresets() async throws -> [IntegrationPreset] {
        let data = try await send(request("/api/auth/integrations/presets"))
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let presets = (d["presets"] as? [String: [String: Any]]) ?? [:]
        return presets.map { key, v in
            IntegrationPreset(id: key, name: (v["name"] as? String) ?? key, authType: (v["auth_type"] as? String) ?? "none",
                              authHeader: (v["auth_header"] as? String) ?? "", description: (v["description"] as? String) ?? "")
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // CalDAV — per-user accounts under /api/calendar/config, NOT generic
    // integrations. 1.8 posted them to /api/auth/integrations: the calendar
    // sync never saw them and the password sat in plaintext.
    func calDAVAccounts() async throws -> [CalDAVAccount] {
        decodeList(CalDAVAccount.self, try await send(request("/api/calendar/config/accounts")))
    }
    /// Real PROPFIND before anything is saved. HTTP 200 either way; `ok` decides.
    func testCalDAV(url: String, username: String, password: String) async throws -> (ok: Bool, error: String) {
        struct B: Encodable { let url: String, username: String, password: String }
        let data = try await send(try jsonRequest("/api/calendar/test", method: "POST", body: B(url: url, username: username, password: password)))
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((d["ok"] as? Bool) ?? false, (d["error"] as? String) ?? "")
    }
    func createCalDAVAccount(label: String, url: String, username: String, password: String) async throws {
        struct B: Encodable { let label: String, url: String, username: String, password: String }
        _ = try await send(try jsonRequest("/api/calendar/config/accounts", method: "POST",
                                           body: B(label: label, url: url, username: username, password: password)))
    }
    func deleteCalDAVAccount(_ id: String) async throws {
        _ = try await send(request("/api/calendar/config/accounts/\(encPath(id))", method: "DELETE"))
    }

    // CardDAV — ONE global admin-owned account behind /api/contacts/config.
    // The PUT takes the prefixed keys; a blank password writes blank.
    func cardDAVConfig() async throws -> (url: String, username: String, hasPassword: Bool) {
        let data = try await send(request("/api/contacts/config"))
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((d["url"] as? String) ?? "", (d["username"] as? String) ?? "", !((d["password"] as? String) ?? "").isEmpty)
    }
    func saveCardDAV(url: String, username: String, password: String) async throws {
        struct B: Encodable { let carddav_url: String, carddav_username: String, carddav_password: String }
        _ = try await send(try jsonRequest("/api/contacts/config", method: "PUT",
                                           body: B(carddav_url: url, carddav_username: username, carddav_password: password)))
    }

    // API tokens — admin only; the raw secret is returned by the POST and never again.
    func apiTokens() async throws -> [APITokenRow] { decodeList(APITokenRow.self, try await send(request("/api/tokens"))) }
    func apiTokenScopes() async throws -> [String] {
        let data = try await send(request("/api/tokens/profiles"))
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (d["allowed_scopes"] as? [String]) ?? []
    }
    /// The route reads `Form(...)` — a JSON body is a 422.
    func createApiToken(name: String, scopes: [String]) async throws -> String {
        let data = try await send(formRequest("/api/tokens", fields: ["name": name, "scopes": scopes.joined(separator: ",")]))
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let t = d["token"] as? String, !t.isEmpty else { throw APIError.decoding("token ausente") }
        return t
    }
    func deleteApiToken(_ id: String) async throws { _ = try await send(request("/api/tokens/\(encPath(id))", method: "DELETE")) }
    /// `PATCH /api/tokens/{id}` is JSON and partial: a body without a
    /// `scopes` key leaves the scopes alone (the server's own regression —
    /// a rename used to reset them to `chat`), so nil here means "not sent".
    /// The reply echoes the merged name and scopes.
    func updateApiToken(_ id: String, name: String?, scopes: [String]?) async throws -> (name: String, scopes: [String]) {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let scopes { body["scopes"] = scopes }
        var req = request("/api/tokens/\(encPath(id))", method: "PATCH")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let d = (try? JSONSerialization.jsonObject(with: try await send(req))) as? [String: Any] ?? [:]
        return ((d["name"] as? String) ?? name ?? "", (d["scopes"] as? [String]) ?? scopes ?? [])
    }
    /// The settings-screen test. The route needs a `test-` note id (admin
    /// only) and the current form as overrides; it answers 200 with the
    /// per-channel error in the body, so a delivery failure is read out of
    /// the reply, not the status.
    func fireTestReminder(channel: String, webhookId: String, template: String,
                          synthesis: Bool, persona: String) async throws {
        struct B: Encodable {
            let note_id: String, title: String, body: String, channel: String
            let webhook_integration_id: String, webhook_payload_template: String
            let llm_synthesis: Bool, llm_persona: String
        }
        let b = B(note_id: "test-" + UUID().uuidString.lowercased(), title: "Odysseus",
                  body: L("Lembrete de teste disparado."), channel: channel,
                  webhook_integration_id: webhookId, webhook_payload_template: template,
                  llm_synthesis: synthesis, llm_persona: persona)
        let data = try await send(try jsonRequest("/api/notes/fire-reminder", method: "POST", body: b))
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let err = d["\(channel)_error"] as? String, !err.isEmpty { throw APIError.transport(err) }
    }

    // Users
    private func userPath(_ username: String) -> String {
        "/api/auth/users/\(username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username)"
    }
    func createUser(username: String, password: String, isAdmin: Bool) async throws {
        struct B: Encodable { let username: String; let password: String; let is_admin: Bool }
        _ = try await send(try jsonRequest("/api/auth/users", method: "POST",
                                           body: B(username: username, password: password, is_admin: isAdmin)))
    }
    // The server has no bare `/users/{username}` write: promote and rename
    // are sub-paths, and delete takes the name in the body. 1.8 hit the bare
    // path for all three and every one 404'd behind a generic "Falha".
    func setUserAdmin(_ username: String, _ isAdmin: Bool) async throws {
        struct B: Encodable { let is_admin: Bool }
        _ = try await send(try jsonRequest(userPath(username) + "/admin", method: "PUT", body: B(is_admin: isAdmin)))
    }
    func renameUser(_ username: String, to newName: String) async throws {
        struct B: Encodable { let username: String }
        _ = try await send(try jsonRequest(userPath(username) + "/rename", method: "PUT", body: B(username: newName)))
    }
    func deleteUser(_ username: String) async throws {
        struct B: Encodable { let username: String }
        _ = try await send(try jsonRequest("/api/auth/users", method: "DELETE", body: B(username: username)))
    }
    /// The reply echoes the merged dict — authoritative, so the row is
    /// replaced from it instead of reloading the list.
    @discardableResult
    func setUserPrivileges(_ username: String, _ p: UserPrivileges) async throws -> UserPrivileges {
        var req = request(userPath(username) + "/privileges", method: "PUT")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: p.payload)
        let d = (try? JSONSerialization.jsonObject(with: try await send(req))) as? [String: Any] ?? [:]
        return UserPrivileges(dict: (d["privileges"] as? [String: Any]) ?? p.payload)
    }
    func signupEnabled() async throws -> Bool {
        let data = try await send(request("/api/auth/policy"))
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (d["signup_enabled"] as? Bool) ?? false
    }
    func toggleSignup() async throws { _ = try await send(request("/api/auth/signup-toggle", method: "POST")) }

    // System
    // streamSession: the default session's 30s resource cap would kill a slow
    // full-backup download mid-transfer (same class of bug as chat uploads).
    func exportData() async throws -> Data { try await send(request("/api/export"), via: streamSession) }
    /// The export file, verbatim. "Nothing recognized" comes back as a 200
    /// with ok:false — read out of the body, like the reminder test.
    func importData(_ json: Data) async throws -> String {
        var req = request("/api/import", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = json
        let data = try await send(req, via: streamSession)
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard d["ok"] as? Bool == true else { throw APIError.transport((d["message"] as? String) ?? "import") }
        return (d["message"] as? String) ?? ""
    }
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
    /// The POST answers 200 whether or not the stdio server came up:
    /// `{id, name, connected, status, tool_count, error, needs_oauth, auth_url}`
    /// (routes/mcp/mcp_routes.py). 1.9 discarded the body, so "npx not found"
    /// or a wrong package closed the sheet as if it had connected.
    func createMCPServer(name: String, transport: String, command: String,
                         args: String, env: String) async throws -> MCPCreateResult {
        let data = try await send(formRequest("/api/mcp/servers", fields: [
            "name": name, "transport": transport, "command": command,
            "args": args, "env": env,
        ]))
        return (try? JSONDecoder().decode(MCPCreateResult.self, from: data)) ?? MCPCreateResult()
    }
}

struct MCPCreateResult: Decodable {
    var connected: Bool = false
    var status: String?
    var toolCount: Int?
    var error: String?
    var needsOAuth: Bool = false
    var needsAuth: Bool = false
    var authURL: String?

    init() {}
    enum CodingKeys: String, CodingKey {
        case connected, status, error
        case toolCount = "tool_count"
        case needsOAuth = "needs_oauth"
        case needsAuth = "needs_auth"
        case authURL = "auth_url"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        connected = (try? c.decodeIfPresent(Bool.self, forKey: .connected)) ?? false
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        toolCount = try? c.decodeIfPresent(Int.self, forKey: .toolCount)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
        needsOAuth = (try? c.decodeIfPresent(Bool.self, forKey: .needsOAuth)) ?? false
        needsAuth = (try? c.decodeIfPresent(Bool.self, forKey: .needsAuth)) ?? false
        authURL = try? c.decodeIfPresent(String.self, forKey: .authURL)
    }
}

// MARK: - Reminders (Lembretes)

@MainActor final class RemindersVM: ObservableObject {
    @Published var channel = "email"
    @Published var emailTo = ""
    @Published var ntfyTopic = ""
    @Published var webhookId = ""
    /// Without it the server refuses to deliver a webhook reminder for any
    /// integration but the Discord preset ("No payload template configured").
    @Published var webhookTemplate = ""
    /// Which connected account sends the reminder; empty = the default one.
    @Published var emailAccountId = ""
    @Published var emailAccounts: [EmailAccount] = []
    @Published var synthesis = false
    @Published var persona = ""
    @Published var loading = false
    @Published var note: String?
    @Published var integrations: [Integration] = []
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    /// The channels the app can honour. "browser" is the server default and
    /// only reaches an open browser tab — it stays selectable when it is what
    /// the server has, so the user can see it and move away from it.
    static let channels: [(id: String, label: String)] = [("email", "Email"), ("ntfy", "ntfy"), ("webhook", "Webhook")]
    /// The five persona ids `src/reminder_personas.py` resolves; anything
    /// else falls back to the neutral tone, which is what 1.8's free-text
    /// field produced every time.
    static let personas: [(id: String, label: String)] = [
        ("", "Padrão"), ("socrates", "Socrates"), ("razor", "Razor"),
        ("nietzsche", "Nietzsche"), ("spark", "Spark"), ("odysseus", "Odysseus"),
    ]

    func load() async {
        loading = true; defer { loading = false }
        let bag = (try? await api.getSettings()) ?? SettingsBag(dict: [:])
        channel = bag.string("reminder_channel").isEmpty ? "email" : bag.string("reminder_channel")
        emailTo = bag.string("reminder_email_to")
        ntfyTopic = bag.string("reminder_ntfy_topic")
        webhookId = bag.string("reminder_webhook_integration_id")
        webhookTemplate = bag.string("reminder_webhook_payload_template")
        emailAccountId = bag.string("reminder_email_account_id")
        emailAccounts = (try? await api.emailAccounts()) ?? []
        if !emailAccounts.contains(where: { $0.id == emailAccountId }) { emailAccountId = emailAccounts.first { $0.isDefault }?.id ?? "" }
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
                "reminder_webhook_payload_template": webhookTemplate,
                "reminder_email_account_id": emailAccountId,
                "reminder_llm_synthesis": synthesis,
                "reminder_llm_persona": persona,
            ])
            note = "Salvo."
        } catch { note = SettingsUI.failure(error, "Falha ao salvar: %@") }
    }
    func test() async {
        note = nil
        do {
            try await api.fireTestReminder(channel: channel, webhookId: webhookId, template: webhookTemplate,
                                           synthesis: synthesis, persona: persona)
            note = "Lembrete de teste disparado."
        } catch { note = SettingsUI.failure(error, "Falha no teste: %@") }
    }
}

struct RemindersSection: View {
    @StateObject private var vm: RemindersVM
    @Environment(\.theme) private var theme
    init(app: AppState) { _vm = StateObject(wrappedValue: RemindersVM(api: app.api)) }

    private var channelOptions: [(id: String, label: String)] {
        (vm.channel == "browser" ? [("browser", "Navegador")] : []) + RemindersVM.channels
    }
    private var personaOptions: [(id: String, label: String)] {
        let known = RemindersVM.personas
        return known.contains { $0.id == vm.persona } ? known : known + [(vm.persona, vm.persona)]
    }
    private func label(_ options: [(id: String, label: String)], _ id: String) -> String {
        options.first { $0.id == id }?.label ?? id
    }
    private var sendFromName: String {
        vm.emailAccounts.first { $0.id == vm.emailAccountId }.map { $0.name.isEmpty ? $0.fromAddress : $0.name } ?? "—"
    }

    var body: some View {
        SettingsScroll("Lembretes", subtitle: "Como o assistente te avisa de lembretes e tarefas.") {
            SettingsCard {
                SettingsUI.menuRow("Canal", value: label(channelOptions, vm.channel), options: channelOptions,
                                   theme: theme) { vm.channel = $0 }
                switch vm.channel {
                case "browser":
                    Text("Só chega ao site aberto no navegador, não ao app.")
                        .font(.ody(size: 10)).foregroundStyle(theme.warning)
                case "email":
                    if vm.emailAccounts.count > 1 {
                        SettingsUI.menuRow("Enviar de", value: sendFromName,
                                           options: vm.emailAccounts.map { (id: $0.id, label: $0.name.isEmpty ? $0.fromAddress : $0.name) },
                                           theme: theme) { vm.emailAccountId = $0 }
                    }
                    SettingsUI.field("Email de destino", $vm.emailTo, placeholder: "voce@exemplo.com", theme: theme)
                case "ntfy":  SettingsUI.field("Tópico ntfy", $vm.ntfyTopic, placeholder: "meu-topico", theme: theme)
                case "webhook":
                    SettingsUI.menuRow("Integração (webhook)", value: webhookName,
                                       options: [(id: "", label: "—")] + vm.integrations.map { (id: $0.id, label: $0.name) },
                                       theme: theme) { vm.webhookId = $0 }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Modelo do payload (JSON)").font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                        TextEditor(text: $vm.webhookTemplate)
                            .font(.ody(size: 12).monospaced()).foregroundStyle(theme.fg)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 72)
                            .padding(6).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                        Text("{{title}} · {{message}}").font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                    }
                default: EmptyView()
                }
                Toggle(isOn: $vm.synthesis) {
                    Text("Resumir com IA").font(.ody(.subheadline)).foregroundStyle(theme.fg)
                }.tint(theme.accent)
                Text("Quando ligado, o modelo utilitário escreve um lembrete curto e acolhedor (uma linha) em vez do conteúdo cru da nota — para browser, email, ntfy e webhook.")
                    .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if vm.synthesis {
                    SettingsUI.menuRow("Persona da IA", value: label(personaOptions, vm.persona), options: personaOptions,
                                       theme: theme) { vm.persona = $0 }
                }
            }
            HStack {
                Button("Testar lembrete") { Task { await vm.test() } }
                    .buttonStyle(.plain).foregroundStyle(theme.fg)
                    .font(.ody(.subheadline))
                Spacer()
                if let n = vm.note { Text(LocalizedStringKey(n)).font(.ody(size: 11)).foregroundStyle(theme.green) }
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
    /// The only limit that stops a runaway agent; the server clamps 0…1000.
    @Published var maxToolCalls = ""
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
        maxRounds = bag.intText("agent_max_rounds")
        maxToolCalls = bag.intText("agent_max_tool_calls")
        tokenBudget = bag.intText("agent_input_token_budget")
        tokenHardMax = bag.intText("agent_input_token_hard_max")
        streamTimeout = bag.intText("agent_stream_timeout_seconds")
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
        catch { toolsNote = SettingsUI.failure(error, "Falha: %@") }
    }
    func save() async {
        note = nil
        var p: [String: Any] = ["agent_email_confirm": emailConfirm]
        for (k, v) in [("agent_max_rounds", maxRounds), ("agent_input_token_budget", tokenBudget),
                       ("agent_input_token_hard_max", tokenHardMax), ("agent_stream_timeout_seconds", streamTimeout)] {
            if let n = Int(v) { p[k] = n }
        }
        if let n = Int(maxToolCalls) {
            let c = min(1000, max(0, n))
            p["agent_max_tool_calls"] = c; maxToolCalls = String(c)
        }
        do { try await api.saveSettings(p); note = "Salvo." }
        catch { note = SettingsUI.failure(error, "Falha: %@") }
    }
    func reconnect(_ s: MCPServer) async {
        do { try await api.reconnectMCP(s.id); await load() }
        catch { note = SettingsUI.failure(error, "Falha ao reconectar: %@") }
    }
}

struct AgentToolsSection: View {
    @StateObject private var vm: AgentToolsVM
    @Environment(\.theme) private var theme
    init(app: AppState) { _vm = StateObject(wrappedValue: AgentToolsVM(api: app.api)) }

    var body: some View {
        SettingsScroll("Agent Tools", subtitle: "Limites de execução do agente e servidores MCP.") {
            SettingsCard {
                Text("Execução").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
                SettingsUI.field("Máx. de rounds", $vm.maxRounds, placeholder: "ex.: 8", theme: theme, numeric: true)
                SettingsUI.field("Máx. de chamadas de ferramenta", $vm.maxToolCalls, placeholder: "0 = ilimitado", theme: theme, numeric: true)
                SettingsUI.field("Orçamento de tokens (entrada)", $vm.tokenBudget, placeholder: "ex.: 120000", theme: theme, numeric: true)
                SettingsUI.field("Teto duro de tokens", $vm.tokenHardMax, placeholder: "ex.: 200000", theme: theme, numeric: true)
                SettingsUI.field("Timeout do stream (s)", $vm.streamTimeout, placeholder: "ex.: 300", theme: theme, numeric: true)
                Toggle(isOn: $vm.emailConfirm) {
                    Text("Confirmar envio de email").font(.ody(.subheadline)).foregroundStyle(theme.fg)
                }.tint(theme.accent)
                HStack {
                    Spacer()
                    if let n = vm.note { Text(LocalizedStringKey(n)).font(.ody(size: 11)).foregroundStyle(theme.green) }
                    SettingsUI.saveButton(theme: theme) { Task { await vm.save() } }
                }
            }
            BuiltinToolsCard(vm: vm)
            SettingsCard {
                Text("Servidores MCP").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
                if vm.servers.isEmpty {
                    Text("Nenhum servidor MCP conectado. Adicione pela web (Admin).")
                        .font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
                }
                ForEach(vm.servers) { s in
                    HStack(spacing: 8) {
                        Circle().fill(s.status == "connected" ? theme.green : theme.secondaryText).frame(width: 7, height: 7)
                        Text(s.name).font(.ody(size: 12)).foregroundStyle(theme.fg)
                        if let st = s.status { Text(st).font(.ody(size: 10)).foregroundStyle(theme.secondaryText) }
                        Spacer()
                        Button("Reconectar") { Task { await vm.reconnect(s) } }
                            .buttonStyle(.plain).foregroundStyle(theme.accent).font(.ody(size: 11))
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
                        .font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
                    Text("Habilite ou desabilite as ferramentas disponíveis ao agente.")
                        .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                }
                Spacer()
                Text("\(enabledCount)/\(vm.tools.count)")
                    .font(.ody(size: 11)).foregroundStyle(theme.accent)
            }
            if vm.tools.isEmpty {
                Text("Carregando…").font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
            }
            ForEach(BuiltinToolCatalog.grouped(vm.tools), id: \.0.id) { cat, items in
                categoryView(cat, items)
            }
            HStack {
                Spacer()
                if let n = vm.toolsNote { Text(LocalizedStringKey(n)).font(.ody(size: 11)).foregroundStyle(theme.green) }
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
                    Text(LocalizedStringKey(cat.label)).font(.ody(size: 12, weight: .medium)).foregroundStyle(theme.fg)
                    Spacer()
                    Text("\(on)/\(items.count)").font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                }
                .padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                HStack(spacing: 10) {
                    Button("Ativar todas") { vm.setCategory(items.map(\.id), enabled: true) }
                        .buttonStyle(.plain).font(.ody(size: 10)).foregroundStyle(theme.accent)
                    Button("Desativar todas") { vm.setCategory(items.map(\.id), enabled: false) }
                        .buttonStyle(.plain).font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                }
                .padding(.leading, 26).padding(.bottom, 4)
                ForEach(items) { t in
                    Toggle(isOn: Binding(get: { t.enabled }, set: { _ in vm.toggleTool(t.id) })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(BuiltinToolCatalog.label(t.id))
                                .font(.ody(size: 12)).foregroundStyle(theme.fg)
                            Text(t.id).font(.ody(size: 9)).foregroundStyle(theme.secondaryText)
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
    @Published var note: String?
    // Terminal logs
    @Published var logs: [String] = []
    @Published var logSearch = ""
    @Published var logLevel = "Todos"
    @Published var logLimit = 100
    @Published var loadingLogs = false
    @Published var logsError: String?
    let logLevels = ["Todos", "INFO", "WARNING", "ERROR", "DEBUG"]
    @Published var autoRefresh = false
    private var pollTask: Task<Void, Never>?
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    /// 3 s, the web's interval. Stopped when the section disappears.
    func setAutoRefresh(_ on: Bool) {
        autoRefresh = on
        pollTask?.cancel()
        pollTask = on ? Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { return }
                await self?.loadLogs()
            }
        } : nil
    }
    func stopPolling() { pollTask?.cancel(); pollTask = nil; autoRefresh = false }

    func importData(_ url: URL) async {
        note = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            note = "Arquivo de backup inválido."; return
        }
        do { let msg = try await api.importData(data); note = L("Importado: %@", msg) }
        catch { note = SettingsUI.failure(error, "Falha ao importar: %@") }
    }
    func load() async {
        let bag = (try? await api.getSettings()) ?? SettingsBag(dict: [:])
        publicURL = bag.string("app_public_url")
        await loadLogs()
    }
    func loadLogs() async {
        loadingLogs = true; logsError = nil; defer { loadingLogs = false }
        do { logs = try await api.diagnosticsLogs(limit: logLimit) }
        catch let e where e.isCancellation {}
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
        catch { note = SettingsUI.failure(error, "Falha: %@") }
    }
    func export() async {
        note = nil
        do {
            let data = try await api.exportData()
            switch await SettingsUI.saveJSON(data, suggested: "odysseus-backup.json") {
            case .some(true):  note = "Backup exportado."
            case .some(false): note = "Falha ao gravar o arquivo do backup."
            case .none:        break   // user cancelled — saying anything would lie
            }
        } catch { note = SettingsUI.failure(error, "Falha ao exportar: %@") }
    }
    /// The eight kinds the server's `DELETE /api/admin/wipe/{kind}` accepts.
    /// "all" is a client-side loop, as on the web — sending it to the server
    /// is a 400 ("Unknown wipe kind: 'all'"), which is what 1.8 did.
    static let wipeKinds = ["chats", "memory", "skills", "notes", "tasks", "documents", "gallery", "calendar"]

    func wipe(_ cat: String) async {
        note = nil
        guard cat == "all" else {
            do { try await api.wipeCategory(cat); note = L("Apagado: %@.", cat) }
            catch { note = SettingsUI.failure(error, "Falha: %@") }
            return
        }
        var failed: [String] = []
        for kind in Self.wipeKinds {
            do { try await api.wipeCategory(kind) }
            catch {
                if error.isCancellation { return }
                failed.append(kind)
            }
        }
        let ok = Self.wipeKinds.count - failed.count
        note = failed.isEmpty
            ? L("Apagado: %lld / %lld categorias.", ok, Self.wipeKinds.count)
            : L("Falha: %@", failed.joined(separator: ", "))
    }
}

struct SistemaSection: View {
    @StateObject private var vm: SistemaVM
    @Environment(\.theme) private var theme
    @State private var confirming: (cat: String, label: String)?
    @State private var picking = false
    @State private var importURL: URL?
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
            if let n = vm.note { Text(LocalizedStringKey(n)).font(.ody(size: 11)).foregroundStyle(theme.green) }
            SettingsCard {
                SettingsUI.field("URL pública do app", $vm.publicURL, placeholder: "https://odysseus.exemplo.com", theme: theme)
                // 2FA is the account's business — Conta has the live control.
                HStack {
                    Spacer()
                    SettingsUI.saveButton(theme: theme) { Task { await vm.save() } }
                }
            }
            SettingsCard {
                Text("Backup de dados").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
                Text("Exporte memórias, presets, settings, skills e preferências como JSON.")
                    .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                Button { Task { await vm.export() } } label: {
                    Label("Exportar dados", systemImage: "square.and.arrow.up")
                        .font(.ody(.subheadline)).foregroundStyle(theme.fg)
                }.buttonStyle(.plain)
                // The import overwrites settings, features and preferences
                // server-side, so it asks before it posts.
                Button { picking = true } label: {
                    Label("Importar dados", systemImage: "square.and.arrow.down")
                        .font(.ody(.subheadline)).foregroundStyle(theme.fg)
                }.buttonStyle(.plain)
            }
            TerminalLogsCard(vm: vm)
            SettingsCard {
                Text("⚠️ Zona de perigo").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.danger)
                Text("Irreversível. Cada item apaga uma categoria.")
                    .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                ForEach(dangers, id: \.cat) { d in
                    Rectangle().fill(theme.border).frame(height: 1)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(d.label)).font(.ody(size: 12)).foregroundStyle(theme.fg)
                            Text(LocalizedStringKey(d.desc)).font(.ody(size: 9)).foregroundStyle(theme.secondaryText).lineLimit(2)
                        }
                        Spacer()
                        Button("Apagar", role: .destructive) { confirming = (d.cat, d.label) }
                            .buttonStyle(.plain).foregroundStyle(theme.danger).font(.ody(size: 12))
                    }
                }
            }
        }
        .task { await vm.load() }
        .onDisappear { vm.stopPolling() }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json], allowsMultipleSelection: false) { r in
            if case .success(let urls) = r, let u = urls.first { importURL = u }
        }
        .alert("Importar backup", isPresented: Binding(get: { importURL != nil }, set: { if !$0 { importURL = nil } })) {
            Button("Importar dados") { if let u = importURL { Task { await vm.importData(u) } }; importURL = nil }
            Button("Cancelar", role: .cancel) { importURL = nil }
        } message: { Text("Substitui memórias, presets, skills, ajustes e preferências do servidor. Confirma?") }
        .alert(LocalizedStringKey(confirming?.label ?? ""), isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
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
        case "ERROR", "CRITICAL": return theme.danger
        case "WARNING": return theme.warning
        case "DEBUG": return theme.secondaryText.opacity(0.7)
        default: return theme.secondaryText
        }
    }

    var body: some View {
        SettingsCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Logs do sistema")
                        .font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
                    Text("Diagnóstico ao vivo do processo Odysseus.")
                        .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                }
                Spacer()
                Toggle(isOn: Binding(get: { vm.autoRefresh }, set: { vm.setAutoRefresh($0) })) {
                    Text("Atualização automática").font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                }
                .toggleStyle(.switch).controlSize(.mini).tint(theme.accent).fixedSize()
                Button { Task { await vm.loadLogs() } } label: {
                    if vm.loadingLogs { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise").font(.ody(size: 12)).foregroundStyle(theme.accent) }
                }.buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                    TextField("Buscar nos logs…", text: $vm.logSearch)
                        .textFieldStyle(.plain).font(.ody(size: 11)).foregroundStyle(theme.fg)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                Menu {
                    ForEach(vm.logLevels, id: \.self) { lv in Button(LocalizedStringKey(lv)) { vm.logLevel = lv } }
                } label: { menuChip(vm.logLevel) }
                Menu {
                    ForEach([100, 200, 500, 1000], id: \.self) { n in
                        Button(L("%lld linhas", n)) { vm.logLimit = n; Task { await vm.loadLogs() } }
                    }
                } label: { menuChip(L("%lld linhas", vm.logLimit)) }
            }
            if let e = vm.logsError {
                Text(L("Falha ao carregar logs: %@", e)).font(.ody(size: 10)).foregroundStyle(theme.danger)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(vm.filteredLogs.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.ody(size: 9))
                            .foregroundStyle(color(SistemaVM.logLevel(line)))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if vm.filteredLogs.isEmpty && !vm.loadingLogs {
                        Text(vm.logs.isEmpty ? "Sem logs." : "Nenhuma linha corresponde ao filtro.")
                            .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                    }
                }
                .padding(8)
            }
            .frame(height: 300)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
            Text("\(vm.filteredLogs.count) de \(vm.logs.count) linhas")
                .font(.ody(size: 9)).foregroundStyle(theme.secondaryText)
        }
    }

    @ViewBuilder private func menuChip(_ label: String) -> some View {
        HStack(spacing: 4) {
            Text(LocalizedStringKey(label)).font(.ody(size: 11)).foregroundStyle(theme.fg)
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
    /// Every visible model of every online endpoint — the allowed-models list.
    @Published var catalog: [(id: String, endpoint: String)] = []
    @Published var shareDefaults = false
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func load() async {
        loading = true; defer { loading = false }
        users = (try? await api.adminUsers()) ?? []
        signupOn = (try? await api.signupEnabled()) ?? false
        shareDefaults = ((try? await api.getSettings()) ?? SettingsBag(dict: [:])).bool("share_defaults_with_users")
        catalog = ((try? await api.modelEndpoints()) ?? []).filter { $0.online != false }
            .flatMap { ep in ep.models.map { (id: $0, endpoint: ep.name) } }
    }
    func setShareDefaults(_ v: Bool) async {
        let old = shareDefaults; shareDefaults = v
        do { try await api.saveSettings(["share_defaults_with_users": v]) }
        catch { shareDefaults = old; note = SettingsUI.failure(error, "Falha: %@") }
    }
    func savePrivileges(_ u: AdminUser, _ p: UserPrivileges) async {
        do {
            let echoed = try await api.setUserPrivileges(u.username, p)
            if let i = users.firstIndex(where: { $0.username == u.username }) { users[i].privileges = echoed }
            note = "Privilégios salvos."
        } catch { note = SettingsUI.failure(error, "Falha ao salvar privilégios: %@", admin: "Só um administrador pode alterar privilégios.") }
    }
    func toggleSignup() async {
        do { try await api.toggleSignup(); signupOn = (try? await api.signupEnabled()) ?? signupOn }
        catch { note = SettingsUI.failure(error, "Falha: %@") }
    }
    func setAdmin(_ u: AdminUser, _ admin: Bool) async {
        do { try await api.setUserAdmin(u.username, admin); await load() }
        catch { note = SettingsUI.failure(error, "Falha: %@") }
    }
    func remove(_ u: AdminUser) async {
        do { try await api.deleteUser(u.username); await load() }
        catch { note = SettingsUI.failure(error, "Falha: %@") }
    }
    func rename(_ u: AdminUser, to name: String) async {
        do { try await api.renameUser(u.username, to: name); await load() }
        catch { note = SettingsUI.failure(error, "Falha: %@") }
    }
    func add() async {
        guard !newUser.isEmpty, newPass.count >= 8 else { note = "Usuário e senha (mín. 8) obrigatórios."; return }
        do {
            try await api.createUser(username: newUser, password: newPass, isAdmin: newAdmin)
            newUser = ""; newPass = ""; newAdmin = false; note = "Usuário criado."; await load()
        } catch { note = SettingsUI.failure(error, "Falha ao criar: %@") }
    }
}

struct UsuariosSection: View {
    @StateObject private var vm: UsuariosVM
    @Environment(\.theme) private var theme
    @State private var renaming: AdminUser?
    @State private var renameText = ""
    @State private var removing: AdminUser?
    @State private var toggling: AdminUser?
    @State private var editingPrivs: AdminUser?
    init(app: AppState) { _vm = StateObject(wrappedValue: UsuariosVM(api: app.api)) }

    var body: some View {
        SettingsScroll("Usuários", subtitle: "Contas com acesso a este servidor.") {
            if let n = vm.note { Text(LocalizedStringKey(n)).font(.ody(size: 11)).foregroundStyle(theme.accent) }
            SettingsCard {
                Toggle(isOn: Binding(get: { vm.signupOn }, set: { _ in Task { await vm.toggleSignup() } })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Cadastro aberto").font(.ody(.subheadline)).foregroundStyle(theme.fg)
                        Text("Qualquer um pode criar conta pela tela de login.")
                            .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                    }
                }.tint(theme.accent)
                Rectangle().fill(theme.border).frame(height: 1)
                Toggle(isOn: Binding(get: { vm.shareDefaults }, set: { v in Task { await vm.setShareDefaults(v) } })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Compartilhar padrões com usuários").font(.ody(.subheadline)).foregroundStyle(theme.fg)
                        Text("Usuários sem padrão próprio herdam o modelo padrão global.")
                            .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                    }
                }.tint(theme.accent)
            }
            ForEach(vm.users) { u in
                SettingsCard {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle").foregroundStyle(theme.accent)
                        Text(u.username).font(.ody(.subheadline)).foregroundStyle(theme.fg)
                        if u.isAdmin {
                            Text("ADMIN").font(.ody(size: 9)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1).background(theme.accent, in: Capsule())
                        }
                        Spacer()
                    }
                    HStack(spacing: 14) {
                        Button(u.isAdmin ? "Revogar admin" : "Tornar admin") { toggling = u }
                            .buttonStyle(.plain).foregroundStyle(theme.fg)
                        Button("Renomear") { renaming = u; renameText = u.username }
                            .buttonStyle(.plain).foregroundStyle(theme.fg)
                        Spacer()
                        // An admin is demoted first, then removed — the web
                        // draws no delete button on admin rows either.
                        if !u.isAdmin {
                            // Admins already hold every privilege; the server 404s on them.
                            Button("Privilégios") { editingPrivs = u }
                                .buttonStyle(.plain).foregroundStyle(theme.fg)
                            Button("Remover", role: .destructive) { removing = u }
                                .buttonStyle(.plain).foregroundStyle(theme.danger)
                        }
                    }
                    .font(.ody(size: 12))
                }
            }
            SettingsCard {
                Text("Adicionar usuário").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
                SettingsUI.field("Usuário", $vm.newUser, placeholder: "nome", theme: theme)
                SettingsUI.field("Senha (mín. 8)", $vm.newPass, placeholder: "••••••••", theme: theme, secure: true)
                HStack {
                    Toggle(isOn: $vm.newAdmin) {
                        Text("Admin").font(.ody(.subheadline)).foregroundStyle(theme.fg)
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
        .alert(removing?.username ?? "", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remover", role: .destructive) { if let u = removing { Task { await vm.remove(u) } }; removing = nil }
            Button("Cancelar", role: .cancel) { removing = nil }
        } message: { Text("Isso é irreversível. Confirma?") }
        .alert(toggling?.username ?? "", isPresented: Binding(get: { toggling != nil }, set: { if !$0 { toggling = nil } })) {
            Button(toggling?.isAdmin == true ? "Revogar admin" : "Tornar admin") {
                if let u = toggling { Task { await vm.setAdmin(u, !u.isAdmin) } }
                toggling = nil
            }
            Button("Cancelar", role: .cancel) { toggling = nil }
        }
        .sheet(item: $editingPrivs) { u in
            UserPrivilegesSheet(user: u, catalog: vm.catalog) { p in await vm.savePrivileges(u, p) }
                .environment(\.theme, theme)
        }
    }
}

// MARK: - Integrações

/// One row of the merged list: the four stores the web's fetchAll reads.
enum IntegrationRow: Identifiable {
    case api(Integration)
    case caldav(CalDAVAccount)
    case carddav(url: String, username: String)
    case token(APITokenRow)

    var id: String {
        switch self {
        case .api(let i): return "api:" + i.id
        case .caldav(let a): return "caldav:" + a.id
        case .carddav: return "carddav"
        case .token(let t): return "token:" + t.id
        }
    }
    var name: String {
        switch self {
        case .api(let i): return i.name
        case .caldav(let a): return a.label
        case .carddav: return L("Contatos (CardDAV)")
        case .token(let t): return t.name
        }
    }
    var detail: String {
        switch self {
        case .api(let i): return i.baseURL ?? ""
        case .caldav(let a): return a.username.isEmpty ? a.url : "\(a.username) · \(a.url)"
        case .carddav(let url, let user): return user.isEmpty ? url : "\(user) · \(url)"
        case .token(let t): return t.tokenPrefix + "… · " + t.scopes.joined(separator: " ")
        }
    }
    var icon: String {
        switch self {
        case .api: return "link"
        case .caldav: return "calendar"
        case .carddav: return "person.crop.circle"
        case .token: return "cpu"
        }
    }
}

@MainActor final class IntegracoesVM: ObservableObject {
    @Published var rows: [IntegrationRow] = []
    @Published var loading = false
    @Published var note: String?
    @Published var noteIsFailure = false
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    /// CalDAV is per user; the other three are admin routes that 403 for
    /// anyone else, so they are only asked for when the caller is admin.
    func load(admin: Bool) async {
        loading = true; defer { loading = false }
        var out: [IntegrationRow] = []
        if admin { out += ((try? await api.integrations()) ?? []).map { .api($0) } }
        out += ((try? await api.calDAVAccounts()) ?? []).map { .caldav($0) }
        if admin, let c = try? await api.cardDAVConfig(), !c.url.isEmpty { out.append(.carddav(url: c.url, username: c.username)) }
        if admin { out += ((try? await api.apiTokens()) ?? []).filter(\.isAgent).map { .token($0) } }
        rows = out
    }
    func test(_ i: Integration) async {
        do {
            let r = try await api.testIntegration(i.id)
            noteIsFailure = !r.ok
            note = r.ok ? L("Teste enviado para %@.", i.name) : L("Falha no teste: %@", r.message.isEmpty ? i.name : r.message)
        } catch { noteIsFailure = true; note = SettingsUI.failure(error, "Falha no teste: %@") }
    }
    func remove(_ row: IntegrationRow, admin: Bool) async {
        do {
            switch row {
            case .api(let i): try await api.deleteIntegration(i.id)
            case .caldav(let a): try await api.deleteCalDAVAccount(a.id)
            case .carddav: try await api.saveCardDAV(url: "", username: "", password: "")   // the web's delete
            case .token(let t): try await api.deleteApiToken(t.id)
            }
            await load(admin: admin)
        } catch { noteIsFailure = true; note = SettingsUI.failure(error, "Falha ao remover: %@") }
    }
}

struct IntegracoesSection: View {
    @StateObject private var vm: IntegracoesVM
    @Environment(\.theme) private var theme
    @EnvironmentObject private var app: AppState
    let host: AppState
    @State private var addKind: IntegrationKind?
    @State private var editing: Integration?
    @State private var removing: IntegrationRow?
    @State private var showEmail = false
    @State private var emailVM: EmailAccountsViewModel
    init(app: AppState) {
        self.host = app
        _vm = StateObject(wrappedValue: IntegracoesVM(api: app.api))
        _emailVM = State(initialValue: EmailAccountsViewModel(api: app.api))
    }
    private var kinds: [IntegrationKind] { IntegrationKind.allCases.filter { app.isAdmin || !$0.adminOnly } }

    var body: some View {
        SettingsScroll("Integrações", subtitle: "Conexões com serviços externos em um só lugar.") {
            Menu {
                if app.isAdmin { Button { showEmail = true } label: { Label("Email (IMAP/SMTP)", systemImage: "envelope") } }
                ForEach(kinds) { k in
                    Button { addKind = k } label: { Label(k.label, systemImage: k.icon) }
                }
            } label: {
                Label("Adicionar integração", systemImage: "plus")
                    .font(.ody(.subheadline)).foregroundStyle(theme.accent)
            }
            .menuStyle(.borderlessButton)

            if vm.loading && vm.rows.isEmpty { ProgressView().tint(theme.accent) }
            if let n = vm.note {
                Text(LocalizedStringKey(n)).font(.ody(size: 11)).foregroundStyle(vm.noteIsFailure ? theme.danger : theme.green)
            }
            if vm.rows.isEmpty && !vm.loading {
                Text("Nenhuma integração ainda — use “Adicionar integração” acima.")
                    .font(.ody(size: 12)).foregroundStyle(theme.secondaryText)
            }
            ForEach(vm.rows) { row in
                SettingsCard {
                    HStack(spacing: 8) {
                        Image(systemName: row.icon).foregroundStyle(theme.accent)
                        Text(row.name).font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg).lineLimit(1)
                        Spacer()
                        if case .api(let i) = row, let t = i.authType { Text(t).font(.ody(size: 9)).foregroundStyle(theme.secondaryText) }
                        if case .token = row { Text("Agente").font(.ody(size: 9)).foregroundStyle(theme.secondaryText) }
                    }
                    if !row.detail.isEmpty {
                        Text(row.detail).font(.ody(size: 10)).foregroundStyle(theme.secondaryText).lineLimit(1)
                    }
                    HStack {
                        if case .api(let i) = row {
                            Button("Testar") { Task { await vm.test(i) } }.buttonStyle(.plain).foregroundStyle(theme.fg)
                            Button("Editar") { editing = i }.buttonStyle(.plain).foregroundStyle(theme.fg)
                        }
                        Spacer()
                        Button("Remover", role: .destructive) { removing = row }
                            .buttonStyle(.plain).foregroundStyle(theme.danger)
                    }
                    .font(.ody(size: 12))
                }
            }
        }
        .task { await vm.load(admin: app.isAdmin) }
        .sheet(item: $addKind) { kind in
            AddIntegrationView(app: host, kind: kind) { Task { await vm.load(admin: app.isAdmin) } }
                .environment(\.theme, theme)
        }
        .sheet(item: $editing) { i in
            AddIntegrationView(app: host, kind: .api, editing: i) { Task { await vm.load(admin: app.isAdmin) } }
                .environment(\.theme, theme)
        }
        .sheet(isPresented: $showEmail) {
            // Same trap as SettingsSections: omitting onTest silently made the
            // connection test a no-op that always reported success.
            NavigationStack {
                AddEmailAccountView(onSave: { payload in await emailVM.add(payload) },
                                    onTest: { payload in await emailVM.test(payload) },
                                    standalone: true)
            }
            .environment(\.theme, theme)
        }
        .alert(removing?.name ?? "", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remover", role: .destructive) { if let r = removing { Task { await vm.remove(r, admin: app.isAdmin) } }; removing = nil }
            Button("Cancelar", role: .cancel) { removing = nil }
        } message: { Text("Isso é irreversível. Confirma?") }
    }
}

// MARK: - Shared small UI helpers
