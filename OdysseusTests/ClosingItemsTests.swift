import XCTest
@testable import Odysseus

/// Round 6 — the five decisions round 5 took without asking, closed by
/// code: interface visibility (the web's Customize UI), token scopes that
/// can be chosen and edited, the notification read shared with the
/// background refresh, and de-AT folded into de (in AppLanguageTests).
@MainActor
final class ClosingItemsTests: XCTestCase {

    override func setUp() { super.setUp(); StubTransport.reset() }
    override func tearDown() {
        StubTransport.reset()
        UserDefaults.standard.removeObject(forKey: TaskNotificationPoller.enabledKey)
        super.tearDown()
    }

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

    // MARK: - Interface visibility

    func testEverythingIsVisibleUntilHidden() {
        let ui = UIVisibility(raw: "")
        XCTAssertTrue(ui.isDefault)
        for k in UIVisibility.Key.allCases { XCTAssertTrue(ui.isOn(k), k.rawValue) }
        for s in AppSection.allCases { XCTAssertTrue(ui.shows(s)) }
    }

    func testHiddenIdsRoundTripSortedAndUnknownOnesAreDropped() {
        var ui = UIVisibility(raw: "composer.web,nope.gone,sidebar.notes")
        XCTAssertEqual(ui.raw, "composer.web,sidebar.notes", "an id that no longer exists cannot hide anything")
        XCTAssertFalse(ui.isOn(.webChip)); XCTAssertFalse(ui.shows(.notes)); XCTAssertTrue(ui.shows(.brain))
        ui.set(.webChip, on: true); ui.set(.thinking, on: false)
        XCTAssertEqual(UIVisibility(raw: ui.raw), ui)
        XCTAssertEqual(ui.raw, "chat.thinking,sidebar.notes")
    }

    func testTheSpacesSwitchHidesEverySectionLikeTheWebsToolsSection() {
        var ui = UIVisibility(raw: "")
        ui.set(.spaces, on: false)
        for s in AppSection.allCases { XCTAssertFalse(ui.shows(s), "\(s)") }
        XCTAssertTrue(ui.isOn(.brain), "the row's own state is kept, so turning Espaços back on restores it")
        XCTAssertTrue(ui.isOn(.deepSearch), "Deep Search is not a section")
        ui.set(.spaces, on: true)
        XCTAssertTrue(ui.shows(.brain))
    }

    func testResetClearsOneGroupOnly() {
        var ui = UIVisibility(raw: "chat.welcome,composer.mic,sidebar.email")
        ui.reset(.composer)
        XCTAssertEqual(ui.raw, "chat.welcome,sidebar.email")
        XCTAssertTrue(UIVisibility.Key.allCases.filter { $0.group == .composer }.allSatisfy { ui.isOn($0) })
    }

    func testEveryKeyHasACatalogueTitle() throws {
        let appBundle = Bundle(for: LocalizationManager.self)
        let en = try XCTUnwrap(Bundle(path: try XCTUnwrap(appBundle.path(forResource: "en", ofType: "lproj"))))
        // A sentinel, not the key: several English values ARE the key
        // ("Brain", "Deep Search"), which `value: nil` cannot tell from a miss.
        for k in UIVisibility.Key.allCases {
            XCTAssertNotEqual(en.localizedString(forKey: k.title, value: "\u{0}MISS", table: nil), "\u{0}MISS", "\(k.rawValue): \"\(k.title)\" is not in the catalogues")
        }
        for g in UIVisibility.Group.allCases {
            XCTAssertNotEqual(en.localizedString(forKey: g.title, value: "\u{0}MISS", table: nil), "\u{0}MISS", "\(g.rawValue)")
        }
    }

    // MARK: - Token scopes: chosen on creation, edited later

    func testAnAgentCarriesThePickedScopesAndLoadsTheServersList() async {
        StubTransport.route("/api/tokens/profiles", .json(#"{"allowed_scopes": ["chat", "memory:read", "todos:read"]}"#))
        StubTransport.route("/api/tokens", .json(#"{"id": "t1", "token": "ody_abc", "scopes": ["chat", "todos:read"]}"#))
        let vm = AddIntegrationVM(api: client(), kind: .codex)
        await vm.loadPresets()
        XCTAssertEqual(vm.allowedScopes, ["chat", "memory:read", "todos:read"])
        vm.name = "laptop"; vm.scopes = ["todos:read", "chat"]
        _ = await vm.save()
        XCTAssertEqual(form("/api/tokens")["scopes"], "chat,todos:read", "sorted, comma-joined — what `_normalize_scopes` reads")
        XCTAssertEqual(form("/api/tokens")["name"], "Codex Agent — laptop")
    }

    func testAnEmptyScopeListFallsBackToTheKnownScopes() async {
        StubTransport.route("/api/tokens/profiles", .json(#"{"allowed_scopes": []}"#))
        let vm = AddIntegrationVM(api: client(), kind: .claude)
        await vm.loadPresets()
        XCTAssertEqual(vm.allowedScopes, TokensVM.fallbackScopes)
    }

    func testARenameAlonePatchesWithoutAScopesKey() async throws {
        StubTransport.route("/api/tokens", .json(#"[{"id": "t1", "name": "old", "token_prefix": "ody_ab", "scopes": ["chat", "todos:read"]}]"#))
        StubTransport.route("/api/tokens/profiles", .json(#"{"allowed_scopes": ["chat", "todos:read"]}"#))
        StubTransport.route("/api/tokens/t1", .json(#"{"id": "t1", "name": "new", "scopes": ["chat", "todos:read"]}"#))
        let vm = TokensVM(api: client())
        await vm.load()
        let t = try XCTUnwrap(vm.items.first)
        let ok = await vm.update(t, name: "new", scopes: ["chat", "todos:read"])
        XCTAssertTrue(ok)
        XCTAssertEqual(StubTransport.methods["/api/tokens/t1"], "PATCH")
        let b = json("/api/tokens/t1")
        XCTAssertEqual(b["name"] as? String, "new")
        XCTAssertNil(b["scopes"], "a scopes key on a rename is what used to reset every token to `chat`")
        XCTAssertEqual(vm.items.first?.name, "new")
        XCTAssertEqual(vm.items.first?.scopes, ["chat", "todos:read"])
    }

    func testAScopeChangeSendsTheWholeListAndAdoptsTheEcho() async throws {
        StubTransport.route("/api/tokens", .json(#"[{"id": "t1", "name": "n", "token_prefix": "ody_ab", "scopes": ["chat"]}]"#))
        StubTransport.route("/api/tokens/t1", .json(#"{"id": "t1", "name": "n", "scopes": ["chat", "memory:read"]}"#))
        let vm = TokensVM(api: client())
        await vm.load()
        let t = try XCTUnwrap(vm.items.first)
        _ = await vm.update(t, name: "n", scopes: ["memory:read", "chat"])
        let b = json("/api/tokens/t1")
        XCTAssertNil(b["name"], "unchanged, not sent")
        XCTAssertEqual(b["scopes"] as? [String], ["chat", "memory:read"])
        XCTAssertEqual(vm.items.first?.scopes, ["chat", "memory:read"])
    }

    func testNothingChangedSendsNothing() async throws {
        StubTransport.route("/api/tokens", .json(#"[{"id": "t1", "name": "n", "token_prefix": "ody_ab", "scopes": ["chat"]}]"#))
        let vm = TokensVM(api: client())
        await vm.load()
        let t = try XCTUnwrap(vm.items.first)
        let ok = await vm.update(t, name: " n ", scopes: ["chat"])
        XCTAssertTrue(ok)
        XCTAssertFalse(StubTransport.requested("/api/tokens/t1"))
    }

    func testAnEmptyScopeSetOnEditMeansChat() async throws {
        StubTransport.route("/api/tokens", .json(#"[{"id": "t1", "name": "n", "token_prefix": "ody_ab", "scopes": ["todos:read"]}]"#))
        StubTransport.route("/api/tokens/t1", .json(#"{"id": "t1", "name": "n", "scopes": ["chat"]}"#))
        let vm = TokensVM(api: client())
        await vm.load()
        _ = await vm.update(try XCTUnwrap(vm.items.first), name: "n", scopes: [])
        XCTAssertEqual(json("/api/tokens/t1")["scopes"] as? [String], ["chat"], "the server grants chat for an empty list; say so")
    }

    // MARK: - Notifications: one read for both paths

    func testOneRefreshPostsEveryEntryWithABody() async {
        UserDefaults.standard.set(true, forKey: TaskNotificationPoller.enabledKey)
        StubTransport.route("/api/tasks/notifications",
                            .json(#"{"notifications": [{"task_name": "Lembrete", "status": "success", "task_id": "reminder-1", "body": "Dentista 15h"}, {"task_name": "silent", "status": "success", "body": ""}]}"#))
        var delivered: [String] = []
        let p = TaskNotificationPoller(api: client())
        p.deliver = { delivered.append($0.body ?? "") }
        let n = await p.refreshOnce()
        XCTAssertEqual(n, 1)
        XCTAssertEqual(delivered, ["Dentista 15h"])
    }

    func testOffMeansNoReadAtAll() async {
        UserDefaults.standard.set(false, forKey: TaskNotificationPoller.enabledKey)
        StubTransport.route("/api/tasks/notifications", .json(#"{"notifications": [{"task_name": "x", "body": "y"}]}"#))
        let p = TaskNotificationPoller(api: client())
        p.deliver = { _ in XCTFail("nothing may be posted while the toggle is off") }
        let n = await p.refreshOnce()
        XCTAssertEqual(n, 0)
        XCTAssertFalse(StubTransport.requested("/api/tasks/notifications"), "the queue drains on read — reading it while off would lose entries the web tab would have shown")
    }

    func testTheBackgroundEntryDoesNotDrainTheQueueWithoutPermission() async {
        UserDefaults.standard.set(true, forKey: TaskNotificationPoller.enabledKey)
        StubTransport.route("/api/tasks/notifications", .json(#"{"notifications": [{"task_name": "x", "body": "y"}]}"#))
        let p = TaskNotificationPoller(api: client())
        p.authorize = { false }
        p.deliver = { _ in XCTFail("no permission, no notification") }
        await p.backgroundRefresh()
        XCTAssertFalse(StubTransport.requested("/api/tasks/notifications"))
        p.authorize = { true }
        var delivered = 0
        p.deliver = { _ in delivered += 1 }
        await p.backgroundRefresh()
        XCTAssertEqual(delivered, 1)
    }
}
