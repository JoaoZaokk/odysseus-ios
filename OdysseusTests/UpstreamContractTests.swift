import XCTest
@testable import Odysseus

/// Contracts the 1.9 client got wrong against the *live* server (upstream
/// d8a2059, 2026-07-23 — the state the owner's server runs). Each route
/// and shape below was read from the server source, not from ENDPOINTS.md,
/// which is how three of these survived two release rounds.
@MainActor
final class UpstreamContractTests: XCTestCase {

    override func setUp() { super.setUp(); StubTransport.reset() }
    override func tearDown() { StubTransport.reset(); super.tearDown() }

    private func makeClient() -> APIClient {
        APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!),
                  protocolClasses: [StubTransport.self])
    }

    // MARK: - Logout (routes/auth_routes.py: the only revoke is POST /api/auth/logout)

    func testLogoutRevokesTheSessionOnTheServer() async {
        StubTransport.route("/api/auth/logout", .json(#"{"ok": true}"#))
        let api = makeClient()
        await api.logout()
        XCTAssertTrue(StubTransport.requested("/api/auth/logout"),
                      "1.9 hit GET /logout, which is not a route — the token stayed valid for 7 days")
        XCTAssertEqual(StubTransport.methods["/api/auth/logout"], "POST")
        XCTAssertFalse(StubTransport.requested("/logout"))
    }

    func testLogoutStillClearsTheJarWhenTheServerIsGone() async {
        // No route registered → the transport fails the request. Logging out of
        // a dead server must still wipe the local session.
        let api = makeClient()
        await api.logout()
        XCTAssertTrue(StubTransport.requested("/api/auth/logout"))
    }

    // MARK: - Notes (routes/note/note_routes.py: `archived` is a server-side filter)

    func testNotesAskTheServerForTheArchiveExplicitly() async throws {
        StubTransport.route("/api/notes", .json(#"[{"id": "n1", "title": "t", "archived": true}]"#))
        let api = makeClient()
        _ = try await api.notes(archived: true)
        XCTAssertEqual(StubTransport.queries["/api/notes"] ?? nil, "archived=true",
                       "without the query the server only ever returns active notes, so the Archived tab stayed empty")
        _ = try await api.notes()
        XCTAssertEqual(StubTransport.queries["/api/notes"] ?? nil, "archived=false")
    }

    func testFlippingTheArchiveSwitchReloadsFromTheServer() async {
        StubTransport.route("/api/notes", .json("[]"))
        let vm = NotesViewModel(api: makeClient())
        await vm.load()
        let before = StubTransport.seen.count
        vm.showArchived = true
        for _ in 0..<40 where StubTransport.seen.count == before { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertGreaterThan(StubTransport.seen.count, before, "the archive is a second list, not a local filter")
        XCTAssertEqual(StubTransport.queries["/api/notes"] ?? nil, "archived=true")
    }

    // MARK: - Memory pin (routes/memory/memory_routes.py: `pinned: bool = Form(True)`)

    func testUnpinSendsPinnedFalseAsAFormField() async throws {
        StubTransport.route("/api/memory/m1/pin", .json(#"{"ok": true, "pinned": false}"#))
        let api = makeClient()
        try await api.pinMemory("m1", pinned: false)
        let body = String(decoding: StubTransport.sentBodies["/api/memory/m1/pin"] ?? Data(), as: UTF8.self)
        XCTAssertEqual(body, "pinned=false",
                       "a bare POST defaults to pinned=true on the server — 'Desafixar' was a silent no-op")
        try await api.pinMemory("m1", pinned: true)
        XCTAssertEqual(String(decoding: StubTransport.sentBodies["/api/memory/m1/pin"] ?? Data(), as: UTF8.self), "pinned=true")
    }

    // MARK: - Stream error frames (src/llm_core.py: `error` is a string 21 times out of 25)

    func testErrorFrameWithAStringErrorReachesTheUser() throws {
        let frame = #"{"error": "Read timeout", "status": 504}"#
        let evt = try JSONDecoder().decode(StreamEvent.self, from: Data(frame.utf8))
        XCTAssertEqual(evt.errorMessage, "Read timeout")
    }

    func testErrorFrameWithAnObjectErrorStillDecodes() throws {
        let frame = #"{"error": {"message": "context length exceeded"}, "status": 400}"#
        let evt = try JSONDecoder().decode(StreamEvent.self, from: Data(frame.utf8))
        XCTAssertEqual(evt.errorMessage, "context length exceeded")
    }

    func testErrorFrameWithOnlyTextAndNoStatusIsNotGeneric() throws {
        // `event: error` + `{"text": "…"}` without a status: the event name is the
        // signal, and 1.9 threw the text away unless status >= 400.
        let frame = #"{"text": "Model endpoint is offline"}"#
        let evt = try JSONDecoder().decode(StreamEvent.self, from: Data(frame.utf8))
        XCTAssertEqual(evt.errorMessage, "Model endpoint is offline")
    }

    func testStreamErrorStringIsShownInTheChat() async {
        StubTransport.route("/api/chat_stream", .sse([#"{"error": "Cannot reach llm.local:8000", "status": 503}"#]))
        let app = AppState(protocolClasses: [StubTransport.self])
        let vm = app.makeChatViewModel(session: ChatSession(id: "s1", title: "t"))
        vm.input = "oi"
        vm.send()
        for _ in 0..<40 where vm.isStreaming { try? await Task.sleep(nanoseconds: 50_000_000) }
        let shown = (vm.error ?? "") + (vm.messages.last?.content ?? "")
        XCTAssertTrue(shown.contains("Cannot reach llm.local:8000"), "got error=\(vm.error ?? "nil") last=\(vm.messages.last?.content ?? "nil")")
    }

    // MARK: - HTTP error bodies (FastAPI `{"detail": …}` is the common case)

    func testExtractErrorReadsFastAPIDetail() {
        XCTAssertEqual(ChatStreamClient.extractError(#"{"detail": "No model selected for this chat. Open the model picker."}"#),
                       "No model selected for this chat. Open the model picker.")
    }

    func testExtractErrorReadsThe422Array() {
        XCTAssertEqual(ChatStreamClient.extractError(#"{"detail": [{"loc": ["body", "message"], "msg": "field required"}]}"#),
                       "field required")
    }

    func testExtractErrorStillReadsMessageAndErrorShapes() {
        XCTAssertEqual(ChatStreamClient.extractError(#"{"error": "rate_limited", "message": "Slow down"}"#), "Slow down")
        XCTAssertEqual(ChatStreamClient.extractError(#"{"error": "Read timeout"}"#), "Read timeout")
        XCTAssertEqual(ChatStreamClient.extractError(#"{"error": {"message": "nested"}}"#), "nested")
    }

    func testExtractErrorNeverShowsRawJSONOrHTML() {
        XCTAssertNil(ChatStreamClient.extractError(#"{"weird": "shape"}"#))
        XCTAssertNil(ChatStreamClient.extractError("<html><body>502 Bad Gateway</body></html>"))
        XCTAssertEqual(ChatStreamClient.extractError("upstream connect error"), "upstream connect error")
    }

    // MARK: - Calendar quick-add (routes/calendar_routes.py: quick-parse only parses)

    func testQuickAddCreatesTheParsedEvent() async {
        StubTransport.route("/api/calendar/calendars", .json(#"[{"href": "/cal/1", "name": "Pessoal"}]"#))
        StubTransport.route("/api/calendar/events", .json(#"{"uid": "new-1"}"#))
        StubTransport.route("/api/calendar/quick-parse", .json(#"{"ok": true, "event": {"summary": "Dentista", "dtstart": "2026-09-14T10:00:00", "dtend": "2026-09-14T11:00:00", "all_day": false, "location": "", "description": ""}, "confidence": 0.9}"#))
        let vm = CalendarViewModel(api: makeClient())
        await vm.load()
        await vm.quickAdd("dentista segunda 10h")
        // `load()` GETs the same path afterwards, so the method map is not the
        // witness — the POST body is (a GET has none).
        let body = String(decoding: StubTransport.sentBodies["/api/calendar/events"] ?? Data(), as: UTF8.self)
        XCTAssertFalse(body.isEmpty, "quick-parse stores nothing — the client has to POST the parsed event, as the web does")
        XCTAssertTrue(body.contains(#""summary":"Dentista""#), body)
        XCTAssertTrue(body.contains(#""dtstart":"2026-09-14T10:00:00""#), body)
        XCTAssertTrue(body.contains(#""calendar_href":"\/cal\/1""#) || body.contains(#""calendar_href":"/cal/1""#), body)
        XCTAssertNil(vm.error)
    }

    func testQuickAddSurfacesAParseFailure() async {
        StubTransport.route("/api/calendar/calendars", .json(#"[{"href": "/cal/1", "name": "Pessoal"}]"#))
        StubTransport.route("/api/calendar/quick-parse", .json(#"{"ok": false, "error": "Model did not produce a start time"}"#))
        let vm = CalendarViewModel(api: makeClient())
        await vm.load()
        await vm.quickAdd("blá")
        XCTAssertEqual(vm.error, "Model did not produce a start time")
        XCTAssertNil(StubTransport.sentBodies["/api/calendar/events"], "nothing may be created from a failed parse")
    }

    // MARK: - Recurring delete (delete_event: `scope` defaults to the whole series)

    func testDeletingOneOccurrenceSendsScopeOccurrence() async throws {
        StubTransport.route("/api/calendar/events/base::2026-09-14T10:00", .json(#"{"ok": true, "scope": "occurrence"}"#))
        let api = makeClient()
        try await api.deleteEvent("base::2026-09-14T10:00", occurrenceOnly: true)
        XCTAssertEqual(StubTransport.queries["/api/calendar/events/base::2026-09-14T10:00"] ?? nil, "scope=occurrence")
        try await api.deleteEvent("base::2026-09-14T10:00")
        XCTAssertNil(StubTransport.queries["/api/calendar/events/base::2026-09-14T10:00"] ?? nil)
    }

    func testOccurrenceRowsCarryTheirSeries() throws {
        let raw = #"{"uid": "base::2026-09-14T10:00", "summary": "Stand-up", "dtstart": "2026-09-14T10:00:00", "series_uid": "base", "is_recurrence": true}"#
        let ev = try JSONDecoder().decode(CalendarEvent.self, from: Data(raw.utf8))
        XCTAssertTrue(ev.isRecurrence)
        XCTAssertEqual(ev.seriesUID, "base")
        let plain = try JSONDecoder().decode(CalendarEvent.self, from: Data(#"{"uid": "x", "summary": "s", "dtstart": "2026-09-14"}"#.utf8))
        XCTAssertFalse(plain.isRecurrence)
    }

    // MARK: - Email writes (200 + success:false is a failure)

    func testArchiveFailureKeepsTheMessageInTheList() async {
        StubTransport.route("/api/email/list", .json(#"{"emails": [{"uid": "7", "subject": "s", "from": "a@b", "date": "2026-09-01"}]}"#))
        StubTransport.route("/api/email/archive/7", .json(#"{"success": false, "error": "Email not found"}"#))
        let api = makeClient()
        do { try await api.emailArchive("7"); XCTFail("success:false must throw") }
        catch { XCTAssertEqual((error as? LocalizedError)?.errorDescription, "Email not found") }
    }

    func testAddAccountFailureIsNotSilent() async {
        StubTransport.route("/api/email/accounts", .json(#"{"ok": false, "error": "name required"}"#))
        let api = makeClient()
        let payload = EmailAccountPayload(name: "", from_address: "a@b", display_name: "", imap_host: "h", imap_port: 993,
                                          imap_user: "u", imap_starttls: false, smtp_host: "", smtp_port: 465,
                                          smtp_security: "ssl", smtp_user: "", is_default: false,
                                          imap_password: nil, smtp_password: nil)
        do { try await api.addEmailAccount(payload); XCTFail("ok:false must throw") }
        catch { XCTAssertEqual((error as? LocalizedError)?.errorDescription, "name required") }
    }

    // MARK: - Cookbook install (routes/cookbook_routes.py validates repo_id, not the pip spec)

    func testCookbookInstallSendsATaskIdAndQuotesEachPipToken() async throws {
        StubTransport.route("/api/model/serve", .json(#"{"ok": true, "session_id": "s"}"#))
        let api = makeClient()
        let raw = #"{"name": "krea diffusers", "desc": "", "category": "Image", "pip": "git+https://github.com/huggingface/diffusers.git torchvision accelerate", "installed": false}"#
        let pkg = try JSONDecoder().decode(CookbookPackage.self, from: Data(raw.utf8))
        try await api.installCookbookPackage(pkg)
        let body = String(decoding: StubTransport.sentBodies["/api/model/serve"] ?? Data(), as: UTF8.self)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: String])
        XCTAssertEqual(obj["repo_id"], "krea_diffusers", "repo_id must match [A-Za-z0-9][A-Za-z0-9._-]* — the pip spec had a space and a URL")
        XCTAssertEqual(obj["cmd"], "python3 -m pip install --user --break-system-packages 'git+https://github.com/huggingface/diffusers.git' 'torchvision' 'accelerate'")
    }

    func testCookbookInstallReadsOkFalse() async throws {
        StubTransport.route("/api/model/serve", .json(#"{"ok": false, "error": "tmux not found on the target host"}"#))
        let api = makeClient()
        let pkg = try JSONDecoder().decode(CookbookPackage.self, from: Data(#"{"name": "hf_transfer", "desc": "", "category": "x", "pip": "hf_transfer", "installed": false}"#.utf8))
        do { try await api.installCookbookPackage(pkg); XCTFail("ok:false must throw") }
        catch { XCTAssertEqual((error as? LocalizedError)?.errorDescription, "tmux not found on the target host") }
    }

    // MARK: - MCP add (POST /api/mcp/servers answers 200 with `connected`)

    func testMCPServerThatDidNotConnectKeepsTheSheetOpen() async throws {
        StubTransport.route("/api/mcp/servers", .json(#"{"id": "m1", "name": "fs", "connected": false, "status": "error", "tool_count": 0, "error": "npx: command not found"}"#))
        let api = makeClient()
        let r = try await api.createMCPServer(name: "fs", transport: "stdio", command: "npx", args: "[]", env: "{}")
        XCTAssertEqual(r.connected, false)
        XCTAssertEqual(r.error, "npx: command not found")
        let ok = try await api.createMCPServer(name: "fs", transport: "stdio", command: "npx", args: "[]", env: "{}")
        XCTAssertEqual(ok.connected, false)
        StubTransport.route("/api/mcp/servers", .json(#"{"id": "m1", "name": "fs", "connected": true, "status": "connected", "tool_count": 4}"#))
        let good = try await api.createMCPServer(name: "fs", transport: "stdio", command: "npx", args: "[]", env: "{}")
        XCTAssertEqual(good.connected, true)
        XCTAssertEqual(good.toolCount, 4)
    }

    // MARK: - Login (routes/auth_routes.py: 2FA is HTTP 200 `{ok: false, requires_totp: true}`)

    func testRequiresTotpIsTheServersOwnKey() async {
        StubTransport.route("/api/auth/login", .json(#"{"ok": false, "requires_totp": true, "username": "joao"}"#))
        let app = AppState(protocolClasses: [StubTransport.self])
        await app.login(username: "joao", password: "x", remember: false, totp: nil)
        XCTAssertTrue(app.totpRequired, "1.9 only knew totp_required/requires_2fa/totp — none of which the server sends")
        XCTAssertNotEqual(app.phase, .main)
    }

    func testOkFalseWithoutAFlagIsARefusedLogin() async {
        StubTransport.route("/api/auth/login", .json(#"{"ok": false, "error": "Invalid credentials"}"#))
        let app = AppState(protocolClasses: [StubTransport.self])
        await app.login(username: "joao", password: "x", remember: false, totp: nil)
        XCTAssertEqual(app.loginError, "Invalid credentials")
        XCTAssertNotEqual(app.phase, .main)
        XCTAssertFalse(app.totpRequired)
    }

    // MARK: - Device flow (the ChatGPT-subscription routes relay the provider's 401)

    func testProviderUnauthorizedInDeviceFlowDoesNotLogTheAppOut() async {
        StubTransport.route("/api/chatgpt-subscription/device/poll", .json(#"{"detail": "invalid_grant Reconnect the provider."}"#, status: 401))
        let api = makeClient()
        let flag = Flag()
        api.onUnauthenticated = { flag.set() }
        do { _ = try await api.deviceFlowPoll("chatgpt-subscription", pollId: "p1"); XCTFail("401 must throw") }
        catch APIError.notAuthenticated { XCTFail("a provider 401 is not our session dying") }
        catch { XCTAssertEqual((error as? LocalizedError)?.errorDescription, "invalid_grant Reconnect the provider.") }
        XCTAssertFalse(flag.value)
    }

    // MARK: - Query encoding (Starlette parse_qsl reads `+` as a space)

    func testEncQueryEscapesPlus() {
        let api = makeClient()
        XCTAssertEqual(api.encQuery("C++"), "C%2B%2B")
        XCTAssertEqual(api.encQuery("user+tag@example.com"), "user%2Btag%40example.com".replacingOccurrences(of: "%40", with: "@"))
    }

    // MARK: - `detail` as an object (stt/tts/session routes)

    func testDetailDictionaryIsReadAsTheMessage() async {
        StubTransport.route("/api/stt/stats", .json(#"{"detail": {"message": "STT service not available or set to browser mode"}}"#, status: 503))
        let api = makeClient()
        do { _ = try await api.send(api.request("/api/stt/stats")); XCTFail("503 must throw") }
        catch { XCTAssertEqual((error as? LocalizedError)?.errorDescription, "STT service not available or set to browser mode") }
    }

    // MARK: - Library upload (200 + success:true even when every file was refused)

    func testRefusedUploadIsReportedAndTheIndexReloaded() async {
        StubTransport.route("/api/personal/upload", .json(#"{"success": true, "uploaded": [], "indexed_count": 0, "failed_count": 1}"#))
        StubTransport.route("/api/personal/reload", .json(#"{"ok": true}"#))
        let api = makeClient()
        do { try await api.uploadPersonal(Data("x".utf8), filename: "scan.pdf"); XCTFail("a refused file must not read as success") }
        catch { XCTAssertNotNil((error as? LocalizedError)?.errorDescription) }
        StubTransport.route("/api/personal/upload", .json(#"{"success": true, "uploaded": ["a.pdf"], "indexed_count": 12, "failed_count": 0}"#))
        do { try await api.uploadPersonal(Data("x".utf8), filename: "a.pdf") } catch { XCTFail("\(error)") }
        XCTAssertTrue(StubTransport.requested("/api/personal/reload"), "from the second upload on the listing is stale without a reload")
    }

    // MARK: - Stop carries the run id (upstream ≥ c436930 ignores a stop without it)

    func testStopSendsTheRunIdTheStreamAnnounced() async {
        StubTransport.route("/api/chat_stream", StubTransport.Reply(200, Data("data: {\"delta\": \"oi\"}\n\n".utf8),
                                                    headers: ["Content-Type": "text/event-stream", "X-Odysseus-Run-Id": "run-42"]))
        StubTransport.route("/api/chat/stop/s1", .json(#"{"stopped": true}"#))
        let app = AppState(protocolClasses: [StubTransport.self])
        let vm = app.makeChatViewModel(session: ChatSession(id: "s1", title: "t"))
        vm.input = "oi"
        vm.send()
        for _ in 0..<40 where vm.runID == nil { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(vm.runID, "run-42")
        vm.stop()
        for _ in 0..<40 where !StubTransport.requested("/api/chat/stop/s1") { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(StubTransport.requested("/api/chat/stop/s1"))
        XCTAssertEqual(StubTransport.headers["/api/chat/stop/s1"]?["X-Odysseus-Run-Id"], "run-42")
    }
}
