import XCTest
@testable import Odysseus

/// The admin writes that 1.8 shipped against routes the server does not
/// have. Every one of these had a green "Salvo"-style path in the UI and a
/// generic "Falha: …" when it ran, and none had a test — which is how a 404
/// on PUT /api/auth/users/{name} survived three releases.
@MainActor
final class AdminRoutesTests: XCTestCase {

    override func setUp() { super.setUp(); StubTransport.reset() }
    override func tearDown() { StubTransport.reset(); super.tearDown() }

    private func client() -> APIClient {
        APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!),
                  protocolClasses: [StubTransport.self])
    }

    private func body(_ path: String) -> [String: Any] {
        guard let d = StubTransport.sentBodies[path] else { return [:] }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
    }

    // MARK: - Users: the three sub-paths the server actually routes

    func testPromotingAUserHitsTheAdminSubPathWithTheFlag() async throws {
        StubTransport.route("/api/auth/users/joao/admin", .json(#"{"ok": true, "is_admin": true, "self": false}"#))
        try await client().setUserAdmin("joao", true)
        XCTAssertEqual(StubTransport.methods["/api/auth/users/joao/admin"], "PUT")
        XCTAssertEqual(body("/api/auth/users/joao/admin")["is_admin"] as? Bool, true)
        XCTAssertFalse(StubTransport.requested("/api/auth/users/joao"), "the bare path is a 404 on the server")
    }

    func testRenamingAUserHitsTheRenameSubPath() async throws {
        StubTransport.route("/api/auth/users/joao/rename", .json(#"{"ok": true, "username": "jose"}"#))
        try await client().renameUser("joao", to: "jose")
        XCTAssertEqual(StubTransport.methods["/api/auth/users/joao/rename"], "PUT")
        XCTAssertEqual(body("/api/auth/users/joao/rename")["username"] as? String, "jose")
    }

    func testDeletingAUserSendsTheNameInTheBodyOfTheCollectionPath() async throws {
        StubTransport.route("/api/auth/users", .json(#"{"ok": true}"#))
        try await client().deleteUser("joao")
        XCTAssertEqual(StubTransport.methods["/api/auth/users"], "DELETE")
        XCTAssertEqual(body("/api/auth/users")["username"] as? String, "joao")
        XCTAssertFalse(StubTransport.requested("/api/auth/users/joao"))
    }

    // MARK: - Wipe: "all" is a loop, not a kind

    func testWipingEverythingWalksTheEightKindsAndSaysSo() async {
        for k in SistemaVM.wipeKinds { StubTransport.route("/api/admin/wipe/\(k)", .json(#"{"ok": true}"#)) }
        let vm = SistemaVM(api: client())
        await vm.wipe("all")
        XCTAssertEqual(StubTransport.seen.filter { $0.hasPrefix("/api/admin/wipe/") }.count, 8)
        XCTAssertFalse(StubTransport.requested("/api/admin/wipe/all"), "the server answers 400 to 'all'")
        XCTAssertEqual(vm.note, "Apagado: 8 / 8 categorias.")
    }

    func testAFailedKindIsNamedAndTheOthersStillRun() async {
        for k in SistemaVM.wipeKinds { StubTransport.route("/api/admin/wipe/\(k)", .json(#"{"ok": true}"#)) }
        StubTransport.route("/api/admin/wipe/gallery", .json(#"{"detail": "disk busy"}"#, status: 500))
        let vm = SistemaVM(api: client())
        await vm.wipe("all")
        XCTAssertEqual(StubTransport.seen.filter { $0.hasPrefix("/api/admin/wipe/") }.count, 8, "one failure must not stop the loop")
        XCTAssertEqual(vm.note, "Falha: gallery")
    }

    func testASingleKindStillGoesStraightToTheServer() async {
        StubTransport.route("/api/admin/wipe/notes", .json(#"{"ok": true}"#))
        let vm = SistemaVM(api: client())
        await vm.wipe("notes")
        XCTAssertEqual(StubTransport.seen, ["/api/admin/wipe/notes"])
        XCTAssertEqual(vm.note, "Apagado: notes.")
    }

    // MARK: - The ADMIN group follows the role

    func testANonAdminGetsNoAdminGroup() {
        let titles = SettingsSection.groups(admin: false).compactMap(\.0)
        XCTAssertFalse(titles.contains("ADMIN"))
        XCTAssertFalse(SettingsSection.groups(admin: false).flatMap(\.1).contains(.users))
        XCTAssertTrue(SettingsSection.groups(admin: true).flatMap(\.1).contains(.users))
    }

    func testTheRoleComesFromStatusAndFailsOpen() throws {
        func status(_ raw: String) throws -> AuthStatus {
            try JSONDecoder().decode(AuthStatus.self, from: Data(raw.utf8))
        }
        XCTAssertFalse(AppState.role(of: try status(#"{"configured": true, "authenticated": true, "username": "u", "is_admin": false}"#)))
        XCTAssertTrue(AppState.role(of: try status(#"{"configured": true, "authenticated": true, "username": "u", "is_admin": true}"#)))
        // An older server that never sends the field must not hide the
        // sections from the one person who runs it.
        XCTAssertTrue(AppState.role(of: try status(#"{"configured": true, "authenticated": true, "username": "u"}"#)))
        // Auth off: there are no roles, so there is nothing to hide.
        XCTAssertTrue(AppState.role(of: try status(#"{"configured": false, "authenticated": false, "is_admin": false}"#)))
    }

    func testBootstrapPublishesTheRole() async {
        StubTransport.route("/api/auth/status", .json(#"{"configured": true, "authenticated": true, "username": "u", "is_admin": false}"#))
        let app = AppState(protocolClasses: [StubTransport.self])
        // `bootstrap()` refuses to talk to an unconfigured (placeholder) server,
        // and `ServerConfig` persists — state the address and put it back.
        let original = app.serverConfig.baseURL
        defer { app.updateServer(original) }
        app.updateServer(URL(string: "https://stub.invalid")!)
        XCTAssertTrue(app.isAdmin, "fails open until the server has spoken")
        await app.bootstrap()
        XCTAssertEqual(app.phase, .main)
        XCTAssertFalse(app.isAdmin)
    }
}
