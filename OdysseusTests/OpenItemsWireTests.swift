import XCTest
@testable import Odysseus

/// The rest of the open-items batch: device flow, email automation, lote 14,
/// the sidebar's date buckets and content search, the notification poller,
/// the shortcut table and the sensitive-text detector.
@MainActor
final class OpenItemsWireTests: XCTestCase {

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

    // MARK: - Device flow

    func testTheDeviceFlowStartsAsAFormAndPollsUntilAuthorized() async {
        StubTransport.route("/api/copilot/device/start", .json(#"{"user_code": "ABCD-1234", "verification_uri": "https://github.com/login/device", "poll_id": "p1", "interval": 1}"#))
        StubTransport.route("/api/copilot/device/poll", .json(#"{"status": "authorized", "endpoint": {"id": "e7", "name": "GitHub Copilot", "models": ["gpt-4o", "o3"]}}"#))
        let vm = DeviceFlowVM(api: client(), provider: .copilot)
        vm.connect()
        for _ in 0..<60 where vm.connectedId == nil { try? await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(vm.connectedId, "e7")
        XCTAssertEqual(vm.models, 2)
        XCTAssertNil(vm.start, "the code card goes away once authorized")
        XCTAssertEqual(StubTransport.methods["/api/copilot/device/start"], "POST")
        XCTAssertEqual(form("/api/copilot/device/poll")["poll_id"], "p1")
    }

    func testAnExpiredDeviceCodeIsSaidInWords() async {
        StubTransport.route("/api/chatgpt-subscription/device/start", .json(#"{"user_code": "XYZ", "verification_uri": "https://auth.openai.com/codex/device", "poll_id": "p2", "interval": 1}"#))
        StubTransport.route("/api/chatgpt-subscription/device/poll", .json(#"{"status": "failed", "error": "expired_token"}"#))
        let vm = DeviceFlowVM(api: client(), provider: .chatgpt)
        vm.connect()
        for _ in 0..<60 where vm.error == nil { try? await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(vm.error, "A sessão de login expirou. Tente de novo.")
        XCTAssertNil(vm.connectedId)
    }

    func testConnectedIsInferredFromTheEndpointHost() throws {
        let rows = try JSONDecoder().decode([ModelEndpoint].self, from: Data(#"[{"id": "e1", "name": "GitHub Copilot", "base_url": "https://api.githubcopilot.com", "models": ["a"], "model_count": 3}]"#.utf8))
        let vm = DeviceFlowVM(api: client(), provider: .copilot)
        vm.loadStatus(rows)
        XCTAssertEqual(vm.connectedId, "e1"); XCTAssertEqual(vm.models, 3)
        let other = DeviceFlowVM(api: client(), provider: .chatgpt)
        other.loadStatus(rows)
        XCTAssertNil(other.connectedId)
    }

    // MARK: - Email automation

    func testTheAutoReplyPutCarriesOnlyItsOwnKeysScopedToTheAccount() async throws {
        StubTransport.route("/api/email/config", .json(#"{"success": true}"#))
        var c = EmailAutomationConfig()
        c.enabled = true; c.message = "Fora"; c.cooldown = "3d"
        try await client().saveEmailAutomationConfig(c, accountId: "acc9")
        XCTAssertEqual(StubTransport.methods["/api/email/config"], "PUT")
        let b = json("/api/email/config")
        XCTAssertEqual(b["email_auto_reply"] as? Bool, true)
        XCTAssertEqual(b["email_auto_reply_scope"] as? String, "account")
        XCTAssertEqual(b["email_auto_reply_account_id"] as? String, "acc9")
        XCTAssertEqual(b["email_auto_reply_cooldown"] as? String, "3d")
        XCTAssertFalse(b.keys.contains { !$0.hasPrefix("email_auto_reply") }, "never a credential key")
    }

    func testAStyleExtractionFailureInsideA200IsAFailure() async {
        StubTransport.route("/api/email/extract-style", .json(#"{"success": false, "error": "Only found 1 usable sent emails, need at least 3"}"#))
        let vm = EmailAutomationVM(api: client())
        await vm.extractStyle()
        XCTAssertEqual(vm.styleNote, "Falha ao extrair estilo: Only found 1 usable sent emails, need at least 3")
    }

    func testTheConfigDecodesTolerantly() throws {
        let c = try JSONDecoder().decode(EmailAutomationConfig.self, from: Data(#"{"smtp_host": "x", "email_auto_reply": true, "email_auto_reply_cooldown": "1d"}"#.utf8))
        XCTAssertTrue(c.enabled); XCTAssertEqual(c.cooldown, "1d")
        XCTAssertTrue(c.excludeAutomated, "the web's default when the key is missing")
    }

    // MARK: - Lote 14

    func testImportReportsA200FailureAsAFailure() async {
        StubTransport.route("/api/import", .json(#"{"ok": false, "message": "No recognized data found in the file"}"#))
        do { _ = try await client().importData(Data("{}".utf8)); XCTFail("must throw") }
        catch { XCTAssertEqual((error as? APIError)?.errorDescription, APIError.transport("No recognized data found in the file").errorDescription) }
    }

    func testToolCallLimitIsClampedLikeTheServer() async {
        StubTransport.route("/api/auth/settings", .json("{}"))
        StubTransport.route("/api/mcp/servers", .json("[]"))
        StubTransport.route("/api/tools", .json(#"{"tools": []}"#))
        let vm = AgentToolsVM(api: client())
        vm.maxToolCalls = "5000"
        await vm.save()
        XCTAssertEqual(json("/api/auth/settings")["agent_max_tool_calls"] as? Int, 1000)
        XCTAssertEqual(vm.maxToolCalls, "1000")
    }

    func testSearchTestReadsTheErrorOutOfA200() async {
        StubTransport.route("/api/search/query", .json(#"{"results": [], "provider": "brave", "error": "Unknown provider"}"#))
        do { _ = try await client().searchTest(provider: "brave"); XCTFail("must throw") }
        catch { XCTAssertTrue("\(error)".contains("Unknown provider")) }
    }

    // MARK: - Sidebar: buckets, groups, content search, stream status

    func testDateBucketsFollowTheWebsRules() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 12))!
        func days(_ n: Int) -> Double { cal.date(byAdding: .day, value: -n, to: now)!.timeIntervalSince1970 }
        XCTAssertEqual(SessionStore.bucket(days(0), now: now), "Hoje")
        XCTAssertEqual(SessionStore.bucket(days(1), now: now), "Ontem")
        XCTAssertFalse(["Hoje", "Ontem"].contains(SessionStore.bucket(days(3), now: now)), "a weekday name from the formatter")
        XCTAssertEqual(SessionStore.bucket(days(45), now: now), L("%d dias atrás", 30))
        XCTAssertEqual(SessionStore.bucket(days(200), now: now), "6 meses atrás")
        XCTAssertEqual(SessionStore.bucket(days(400), now: now), L("%d ano atrás", 1))
        XCTAssertEqual(SessionStore.bucket(nil, now: now), "Mais antigas")
    }

    func testGroupsPutFavoritesFirstAndSplitOnBucketChanges() {
        let now = Date().timeIntervalSince1970
        let list = [ChatSession(id: "p", title: "p", updatedAt: now - 10 * 86_400, pinned: true),
                    ChatSession(id: "a", title: "a", updatedAt: now),
                    ChatSession(id: "b", title: "b", updatedAt: now - 60),
                    ChatSession(id: "c", title: "c", updatedAt: now - 86_400)]
        let g = SessionStore.groups(list)
        XCTAssertEqual(g.map(\.label), ["Favoritos", "Hoje", "Ontem"])
        XCTAssertEqual(g[1].sessions.map(\.id), ["a", "b"])
    }

    func testContentSearchHitsDecodeAndDebounce() async {
        StubTransport.route("/api/search", .json(#"[{"message_id": "m1", "session_id": "s1", "session_name": "Viagem", "role": "assistant", "content_snippet": "…Lisboa…"}]"#))
        let store = SessionStore(api: client())
        store.search("Lis")
        for _ in 0..<40 where store.hits.isEmpty { try? await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(store.hits.first?.sessionName, "Viagem")
        store.search("L")
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(store.hits.isEmpty, "one character is below the threshold and clears the hits")
    }

    func testStreamStatus404IsNotStreaming() async {
        StubTransport.route("/api/chat/stream_status/s1", .json(#"{"detail": "No active stream"}"#, status: 404))
        StubTransport.route("/api/chat/stream_status/s2", .json(#"{"status": "streaming", "partial": ""}"#))
        let c = client()
        let a = await c.isStreaming("s1"), b = await c.isStreaming("s2")
        XCTAssertFalse(a); XCTAssertTrue(b)
    }

    // The notification poller's wire moved to ClosingItemsTests (round 6),
    // where `refreshOnce()` is the seam both paths share.

    // MARK: - Shortcuts and the sensitive-text detector

    func testShortcutCapsRenderMacGlyphs() {
        XCTAssertEqual(OdyShortcuts.send.caps, ["⌘", "↩"])
        XCTAssertEqual(OdyShortcuts.nextChat.caps, ["⌥", "⌘", "↓"])
        XCTAssertEqual(OdyShortcuts.deepSearch.caps, ["⇧", "⌘", "D"])
        XCTAssertEqual(Set(OdyShortcuts.groups.flatMap(\.1).map(\.id)).count, OdyShortcuts.groups.flatMap(\.1).count, "no two bindings share an id")
    }

    func testTheRedactorMatchesTheWebsPatterns() {
        XCTAssertTrue(SensitiveRedactor.hasSensitive("fale com joao@example.com"))
        XCTAssertTrue(SensitiveRedactor.hasSensitive("use sk-abcdefghijklmnopqrstuvwxyz1234"))
        XCTAssertTrue(SensitiveRedactor.hasSensitive("Authorization: Bearer abcdefghijklmnopqrstuvwxyz"))
        XCTAssertTrue(SensitiveRedactor.hasSensitive("password: hunter2!"))
        XCTAssertTrue(SensitiveRedactor.hasSensitive("cartão 4111 1111 1111 1111"))
        XCTAssertFalse(SensitiveRedactor.hasSensitive("A capital de Portugal é Lisboa."))
        XCTAssertFalse(SensitiveRedactor.hasSensitive(""))
    }
}
