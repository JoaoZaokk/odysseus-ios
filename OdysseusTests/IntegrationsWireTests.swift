import XCTest
@testable import Odysseus

/// Integrations, tokens and privileges: every route checked against the
/// server source. 1.8 posted CalDAV/CardDAV accounts and "agents" to the
/// generic integrations route — the calendar never saw the accounts, the
/// passwords sat in plaintext, and the agents 400'd.
@MainActor
final class IntegrationsWireTests: XCTestCase {

    override func setUp() { super.setUp(); StubTransport.reset() }
    override func tearDown() { StubTransport.reset(); super.tearDown() }

    private func client() -> APIClient {
        APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!),
                  protocolClasses: [StubTransport.self])
    }
    private func json(_ path: String) -> [String: Any] {
        guard let d = StubTransport.sentBodies[path] else { return [:] }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
    }
    private func form(_ path: String) -> [String: String] {
        let raw = String(decoding: StubTransport.sentBodies[path] ?? Data(), as: UTF8.self)
        var out: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            out[kv[0].removingPercentEncoding ?? kv[0]] = kv[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? kv[1]
        }
        return out
    }

    // MARK: - CalDAV goes to the calendar store, after a real test

    func testCalDAVIsTestedThenSavedUnderTheCalendarConfig() async {
        StubTransport.route("/api/calendar/test", .json(#"{"ok": true}"#))
        StubTransport.route("/api/calendar/config/accounts", .json(#"{"ok": true, "id": "a1"}"#))
        let vm = AddIntegrationVM(api: client(), kind: .caldav)
        vm.name = "Trabalho"; vm.url = "https://cal.example/dav/"; vm.username = "joao"; vm.password = "s3cret"
        let ok = await vm.save()
        XCTAssertTrue(ok)
        XCTAssertEqual(StubTransport.seen, ["/api/calendar/test", "/api/calendar/config/accounts"], "test first, then save")
        XCTAssertEqual(StubTransport.methods["/api/calendar/config/accounts"], "POST")
        let b = json("/api/calendar/config/accounts")
        XCTAssertEqual(Set(b.keys), ["label", "url", "username", "password"])
        XCTAssertFalse(StubTransport.requested("/api/auth/integrations"), "the generic store never sees a CalDAV account again")
    }

    func testAFailedCalDAVTestSavesNothingAndNamesTheReason() async {
        StubTransport.route("/api/calendar/test", .json(#"{"ok": false, "error": "Auth failed — check username/password"}"#))
        let vm = AddIntegrationVM(api: client(), kind: .caldav)
        vm.url = "https://cal.example/dav/"; vm.username = "joao"; vm.password = "wrong"
        let saved = await vm.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(vm.error, "Auth failed — check username/password")
        XCTAssertFalse(StubTransport.requested("/api/calendar/config/accounts"))
    }

    func testCalDAVRefusesAnEmptyPasswordBeforeTouchingTheNetwork() async {
        let vm = AddIntegrationVM(api: client(), kind: .caldav)
        vm.url = "https://cal.example/dav/"; vm.username = "joao"
        let saved = await vm.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(vm.error, "Senha é obrigatória.")
        XCTAssertTrue(StubTransport.seen.isEmpty)
    }

    // MARK: - CardDAV is one global account with prefixed keys

    func testCardDAVPutsThePrefixedKeys() async {
        StubTransport.route("/api/contacts/config", .json(#"{"success": true}"#))
        let vm = AddIntegrationVM(api: client(), kind: .carddav)
        vm.url = "http://radicale:5232/joao/contacts/"; vm.username = "joao"; vm.password = "pw"
        let saved = await vm.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(StubTransport.methods["/api/contacts/config"], "PUT")
        XCTAssertEqual(Set(json("/api/contacts/config").keys), ["carddav_url", "carddav_username", "carddav_password"],
                       "a body carrying url/password would be silently ignored by the server")
    }

    // MARK: - Agents are API tokens

    func testAnAgentIsAFormPostToTokensAndStaysOnScreen() async {
        StubTransport.route("/api/tokens", .json(#"{"id": "t1", "token": "ody_abc", "scopes": ["chat"]}"#))
        let vm = AddIntegrationVM(api: client(), kind: .claude)
        vm.name = "laptop"
        let dismissed = await vm.save()
        XCTAssertFalse(dismissed, "the sheet must stay open: the token is shown once")
        XCTAssertEqual(vm.createdToken, "ody_abc")
        XCTAssertEqual(StubTransport.methods["/api/tokens"], "POST")
        let f = form("/api/tokens")
        XCTAssertEqual(f["name"], "Claude Agent — laptop", "the web classifies agents by this name prefix")
        XCTAssertEqual(f["scopes"], "chat")
        XCTAssertFalse(StubTransport.requested("/api/auth/integrations"), "this is the 400 1.8 shipped")
    }

    // MARK: - API integrations: presets, basic auth, edit, honest test

    func testAPresetFlowsIntoTheCreateBody() async {
        StubTransport.route("/api/auth/integrations/presets",
                            .json(#"{"presets": {"ntfy": {"name": "ntfy", "auth_type": "bearer", "auth_header": "", "description": "push"}}}"#))
        StubTransport.route("/api/auth/integrations", .json(#"{"ok": true, "integration": {"id": "i1"}}"#))
        let vm = AddIntegrationVM(api: client(), kind: .api)
        await vm.loadPresets()
        vm.applyPreset("ntfy")
        vm.baseURL = "https://ntfy.sh"
        let saved = await vm.save()
        XCTAssertTrue(saved)
        let b = json("/api/auth/integrations")
        XCTAssertEqual(b["preset"] as? String, "ntfy", "without it the server's ntfy test branch never fires")
        XCTAssertEqual(b["auth_type"] as? String, "bearer")
        XCTAssertEqual(b["name"] as? String, "ntfy")
    }

    func testBasicAuthIsOffered() async {
        StubTransport.route("/api/auth/integrations", .json(#"{"ok": true}"#))
        let vm = AddIntegrationVM(api: client(), kind: .api)
        vm.name = "Gitea"; vm.baseURL = "https://git.example"; vm.authType = "basic"; vm.apiKey = "joao:pw"
        let saved = await vm.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(json("/api/auth/integrations")["auth_type"] as? String, "basic")
        XCTAssertTrue(AddIntegrationVM.authTypes.contains { $0.id == "basic" })
    }

    func testEditingPutsWithoutResendingTheMaskedKey() async throws {
        let existing = try JSONDecoder().decode(Integration.self, from: Data(#"{"id": "i9", "name": "Miniflux", "base_url": "https://rss", "auth_type": "header", "auth_header": "X-Auth-Token", "preset": "miniflux", "api_key": "abcd****"}"#.utf8))
        StubTransport.route("/api/auth/integrations/i9", .json(#"{"ok": true}"#))
        let vm = AddIntegrationVM(api: client(), kind: .api, editing: existing)
        XCTAssertEqual(vm.authHeader, "X-Auth-Token")
        vm.name = "Miniflux casa"
        let saved = await vm.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(StubTransport.methods["/api/auth/integrations/i9"], "PUT")
        let b = json("/api/auth/integrations/i9")
        XCTAssertNil(b["api_key"], "blank on PUT keeps the stored secret; the masked value must never go back")
        XCTAssertEqual(b["name"] as? String, "Miniflux casa")
        XCTAssertFalse(StubTransport.requested("/api/auth/integrations"))
    }

    func testAFailedIntegrationTestIsAFailureNotASend() async {
        StubTransport.route("/api/auth/integrations/i1/test", .json(#"{"ok": false, "message": "Connection failed"}"#))
        let vm = IntegracoesVM(api: client())
        let i = try! JSONDecoder().decode(Integration.self, from: Data(#"{"id": "i1", "name": "Svc"}"#.utf8))
        await vm.test(i)
        XCTAssertTrue(vm.noteIsFailure)
        XCTAssertEqual(vm.note, "Falha no teste: Connection failed")
    }

    func testTheListMergesTheFourStoresForAnAdmin() async {
        StubTransport.route("/api/auth/integrations", .json(#"{"integrations": [{"id": "i1", "name": "Svc"}]}"#))
        StubTransport.route("/api/calendar/config/accounts", .json(#"{"accounts": [{"id": "c1", "label": "Casa", "url": "https://cal", "username": "j"}]}"#))
        StubTransport.route("/api/contacts/config", .json(#"{"url": "http://radicale", "username": "j", "password": "***"}"#))
        StubTransport.route("/api/tokens", .json(#"[{"id": "t1", "name": "Claude Agent — laptop", "token_prefix": "ody_ab", "scopes": ["chat"]}, {"id": "t2", "name": "backup script", "token_prefix": "ody_cd", "scopes": ["chat"]}]"#))
        let vm = IntegracoesVM(api: client())
        await vm.load(admin: true)
        XCTAssertEqual(vm.rows.map(\.id), ["api:i1", "caldav:c1", "carddav", "token:t1"], "only agent tokens; the script token belongs to Tokens de API")
    }

    func testANonAdminOnlySeesTheirCalDAVAccounts() async {
        StubTransport.route("/api/calendar/config/accounts", .json(#"{"accounts": [{"id": "c1", "label": "Casa", "url": "https://cal", "username": "j"}]}"#))
        let vm = IntegracoesVM(api: client())
        await vm.load(admin: false)
        XCTAssertEqual(vm.rows.map(\.id), ["caldav:c1"])
        XCTAssertFalse(StubTransport.requested("/api/auth/integrations"), "an admin route would only 403")
        XCTAssertFalse(StubTransport.requested("/api/tokens"))
    }

    // MARK: - Tokens section

    func testCreatingATokenRevealsItOnceAndReloads() async {
        StubTransport.route("/api/tokens/profiles", .json(#"{"allowed_scopes": ["chat", "todos:read"]}"#))
        StubTransport.route("/api/tokens", .json(#"{"id": "t1", "token": "ody_new", "scopes": ["chat", "todos:read"]}"#))
        let vm = TokensVM(api: client())
        await vm.load()
        XCTAssertEqual(vm.allowedScopes, ["chat", "todos:read"])
        vm.newName = "script"; vm.newScopes = ["chat", "todos:read"]
        await vm.create()
        XCTAssertEqual(vm.revealed, "ody_new")
        XCTAssertEqual(form("/api/tokens")["scopes"], "chat,todos:read")
        XCTAssertEqual(vm.newName, "")
    }

    func testRevokeIsADeleteAndRemovesTheRow() async throws {
        StubTransport.route("/api/tokens/t1", .json(#"{"status": "deleted"}"#))
        let vm = TokensVM(api: client())
        let row = try JSONDecoder().decode(APITokenRow.self, from: Data(#"{"id": "t1", "name": "x", "token_prefix": "ody_", "scopes": []}"#.utf8))
        vm.items = [row]
        await vm.revoke(row)
        XCTAssertEqual(StubTransport.methods["/api/tokens/t1"], "DELETE")
        XCTAssertTrue(vm.items.isEmpty)
    }

    // MARK: - Privileges

    func testPrivilegesPutAllElevenKeysAndAdoptTheEcho() async throws {
        StubTransport.route("/api/auth/users/ana/privileges",
                            .json(#"{"ok": true, "privileges": {"can_use_bash": true, "max_messages_per_day": 50, "allowed_models": ["m1"], "allowed_models_restricted": true}}"#))
        var p = UserPrivileges()
        p.canUseBash = true; p.maxMessagesPerDay = 50; p.allowedModels = ["m1"]; p.allowedModelsRestricted = true
        let echoed = try await client().setUserPrivileges("ana", p)
        XCTAssertEqual(StubTransport.methods["/api/auth/users/ana/privileges"], "PUT")
        XCTAssertEqual(json("/api/auth/users/ana/privileges").count, 11, "one PUT with every key, as the server's whitelist expects")
        XCTAssertEqual(echoed.maxMessagesPerDay, 50)
        XCTAssertEqual(echoed.allowedModels, ["m1"])
        XCTAssertTrue(echoed.canUseAgent, "absent keys in the echo keep the defaults")
    }

    func testAUserRowWithoutPrivilegesFallsBackToTheServersDefaults() throws {
        let u = try JSONDecoder().decode(AdminUser.self, from: Data(#"{"username": "old", "is_admin": false}"#.utf8))
        XCTAssertFalse(u.privileges.canUseBash, "bash is the one default that is off")
        XCTAssertTrue(u.privileges.canUseResearch)
        XCTAssertEqual(u.privileges.maxMessagesPerDay, 0)
    }
}
