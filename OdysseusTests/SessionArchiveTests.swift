import XCTest
@testable import Odysseus

/// Pin and archive from the sidebar. 1.8 decoded `is_important` and drew the
/// pin, hid archived chats, and offered only a one-tap delete that is final
/// on the server — with no endpoint for any of the three.
@MainActor
final class SessionArchiveTests: XCTestCase {

    override func setUp() { super.setUp(); StubTransport.reset() }
    override func tearDown() { StubTransport.reset(); super.tearDown() }

    private func client() -> APIClient {
        APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!),
                  protocolClasses: [StubTransport.self])
    }

    private let live = #"""
    [{"id": "a", "name": "Alpha", "updated_at": "2026-09-01T10:00:00", "is_important": false},
     {"id": "b", "name": "Beta",  "updated_at": "2026-09-02T10:00:00", "is_important": true},
     {"id": "z", "name": "Zeta",  "updated_at": "2026-09-03T10:00:00", "archived": true}]
    """#

    func testTheLoadReportsTheLiveCountAndHidesArchived() async {
        StubTransport.route("/api/sessions", .json(live))
        var reported = -1
        let store = SessionStore(api: client()) { reported = $0 }
        await store.load()
        XCTAssertEqual(store.sessions.map(\.id), ["b", "a"], "pinned first, then most recent")
        XCTAssertEqual(reported, 2, "the review gate must not count archived chats")
    }

    func testArchivingTakesTheRowOffTheListAndTellsTheCount() async {
        StubTransport.route("/api/sessions", .json(live))
        StubTransport.route("/api/session/a/archive", .json(#"{"ok": true}"#))
        var reported = -1
        let store = SessionStore(api: client()) { reported = $0 }
        await store.load()
        await store.archive(ChatSession(id: "a", title: "Alpha"))
        XCTAssertEqual(StubTransport.methods["/api/session/a/archive"], "POST")
        XCTAssertEqual(store.sessions.map(\.id), ["b"])
        XCTAssertEqual(reported, 1)
        XCTAssertNil(store.error)
    }

    func testPinningPostsTheFormFlagAndResorts() async {
        StubTransport.route("/api/sessions", .json(live))
        StubTransport.route("/api/session/a/important", .json(#"{"status": "success", "is_important": true}"#))
        let store = SessionStore(api: client())
        await store.load()
        await store.setPinned(ChatSession(id: "a", title: "Alpha"), true)
        XCTAssertEqual(StubTransport.methods["/api/session/a/important"], "POST")
        let body = String(decoding: StubTransport.sentBodies["/api/session/a/important"] ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains(#"name="important""#) && body.contains("true"), "FastAPI reads `important` from a form field")
        XCTAssertTrue(store.sessions.first { $0.id == "a" }?.pinned ?? false)
    }

    func testUnpinningSendsFalseNotAnAbsentField() async {
        StubTransport.route("/api/session/b/important", .json(#"{"status": "success", "is_important": false}"#))
        let store = SessionStore(api: client())
        await store.setPinned(ChatSession(id: "b", title: "Beta", pinned: true), false)
        let body = String(decoding: StubTransport.sentBodies["/api/session/b/important"] ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("false"), "the server's default for a missing field is true")
    }

    func testTheArchiveListDecodesTheWrappedShape() async {
        StubTransport.route("/api/sessions/archived",
                            .json(#"{"sessions": [{"id": "z", "name": "Zeta", "is_important": false}], "total": 1}"#))
        let store = SessionStore(api: client())
        await store.loadArchived()
        XCTAssertEqual(store.archived.map(\.title), ["Zeta"])
    }

    func testUnarchivingReturnsTheChatToTheList() async {
        StubTransport.route("/api/session/z/unarchive", .json(#"{"ok": true}"#))
        StubTransport.route("/api/sessions", .json(#"[{"id": "z", "name": "Zeta"}]"#))
        let store = SessionStore(api: client())
        store.archived = [ChatSession(id: "z", title: "Zeta")]
        await store.unarchive(ChatSession(id: "z", title: "Zeta"))
        XCTAssertEqual(StubTransport.methods["/api/session/z/unarchive"], "POST")
        XCTAssertTrue(store.archived.isEmpty)
        XCTAssertEqual(store.sessions.map(\.id), ["z"], "the list is reloaded so the row comes back")
    }

    func testARejectedArchiveKeepsTheRowAndSaysWhy() async {
        StubTransport.route("/api/sessions", .json(live))
        StubTransport.route("/api/session/a/archive", .json(#"{"detail": "Session not found"}"#, status: 404))
        let store = SessionStore(api: client())
        await store.load()
        await store.archive(ChatSession(id: "a", title: "Alpha"))
        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertNotNil(store.error)
    }
}
