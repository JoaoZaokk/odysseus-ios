import XCTest
@testable import Odysseus

/// The 401 wire: the server rejects the session, `APIClient` calls back, and
/// `AppState` — the only owner of session state — reacts.
///
/// `AppState` held 109 untested lines across seven session methods before the
/// transport seam existed. This covers the path that decides whether an expired
/// cookie throws the user back to login or leaves them on the main screen with
/// every list failing silently, plus the Keychain policy around it, which is
/// where a real defect was found: unchecking "keep me signed in" left the
/// credentials from a previous login on the device.
@MainActor
final class SessionWireTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubTransport.reset()
        clearKeychain()
    }

    override func tearDown() {
        StubTransport.reset()
        clearKeychain()
        super.tearDown()
    }

    private func clearKeychain() {
        _ = Keychain.delete(Keychain.usernameKey)
        _ = Keychain.delete(Keychain.passwordKey)
        _ = Keychain.delete(Keychain.cookiesKey)
    }

    // MARK: - 401 → sessionExpired → .login

    func testA401ThrowsTheUserBackToLoginWithAReason() async {
        StubTransport.route("/api/memory", .json(#"{"detail": "session gone"}"#, status: 401))
        let app = AppState(protocolClasses: [StubTransport.self])
        app.phase = .main

        _ = try? await app.api.memories()
        // `onUnauthenticated` hops to the main actor, so let that hop land.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(app.phase, .login)
        XCTAssertEqual(app.loginError, APIError.notAuthenticated.errorDescription,
                       "landing on the login screen with no reason reads as a crash")
        XCTAssertNil(app.username)
    }

    func testA403LeavesTheUserWhereTheyAre() async {
        StubTransport.route("/api/memory", .json(#"{"detail": "admin only"}"#, status: 403))
        let app = AppState(protocolClasses: [StubTransport.self])
        app.phase = .main

        _ = try? await app.api.memories()
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(app.phase, .main, "403 is 'you may not', not 'you are not'")
        XCTAssertNil(app.loginError)
    }

    func testSessionExpiredIsIgnoredWhenAlreadyAtLogin() {
        let app = AppState(protocolClasses: [StubTransport.self])
        app.phase = .login
        app.loginError = nil

        app.sessionExpired()

        XCTAssertNil(app.loginError, "a second 401 must not overwrite a real login error")
    }

    // MARK: - What an expiry keeps, and what it throws away

    func testAnExpiryKeepsTheCredentialsAndDropsTheDeadCookie() {
        _ = Keychain.set("joao", for: Keychain.usernameKey)
        _ = Keychain.set("hunter2", for: Keychain.passwordKey)
        _ = Keychain.set("YXJjaGl2ZWQ=", for: Keychain.cookiesKey)
        let app = AppState(protocolClasses: [StubTransport.self])
        app.phase = .main

        app.sessionExpired()

        // Deliberate: the credentials are still good, it is the cookie that died,
        // so the next cold launch can auto-login.
        XCTAssertEqual(Keychain.get(Keychain.usernameKey), "joao")
        XCTAssertEqual(Keychain.get(Keychain.passwordKey), "hunter2")
        // The archived copy is the same dead cookie. Keeping it kept a known-dead
        // session on the device until the next successful login.
        XCTAssertNil(Keychain.get(Keychain.cookiesKey))
    }

    func testLoggingOutForgetsEverything() async {
        StubTransport.route("/api/auth/logout", .json("{}"))
        _ = Keychain.set("joao", for: Keychain.usernameKey)
        _ = Keychain.set("hunter2", for: Keychain.passwordKey)
        _ = Keychain.set("YXJjaGl2ZWQ=", for: Keychain.cookiesKey)
        let app = AppState(protocolClasses: [StubTransport.self])
        app.phase = .main

        await app.logout()

        XCTAssertNil(Keychain.get(Keychain.usernameKey))
        XCTAssertNil(Keychain.get(Keychain.passwordKey))
        XCTAssertNil(Keychain.get(Keychain.cookiesKey))
        XCTAssertEqual(app.phase, .login)
        XCTAssertNil(app.username)
    }

    // `ServerConfig` persists, so these two must state their own starting point
    // and put it back. Deriving the target from whatever happened to be saved is
    // how the first version of this test passed alone and failed in the suite.

    func testSwitchingServersForgetsTheOldAccount() {
        let app = AppState(protocolClasses: [StubTransport.self])
        let original = app.serverConfig.baseURL
        defer { app.updateServer(original) }
        app.updateServer(URL(string: "https://servidor-a.invalid")!)
        app.phase = .main
        _ = Keychain.set("joao", for: Keychain.usernameKey)
        _ = Keychain.set("hunter2", for: Keychain.passwordKey)

        app.updateServer(URL(string: "https://servidor-b.invalid")!)

        // Server A's credentials must never reach server B.
        XCTAssertNil(Keychain.get(Keychain.usernameKey))
        XCTAssertNil(Keychain.get(Keychain.passwordKey))
        XCTAssertEqual(app.phase, .login)
    }

    func testSwitchingToTheSameServerChangesNothing() {
        let app = AppState(protocolClasses: [StubTransport.self])
        let original = app.serverConfig.baseURL
        defer { app.updateServer(original) }
        app.updateServer(URL(string: "https://servidor-a.invalid")!)
        app.phase = .main
        _ = Keychain.set("joao", for: Keychain.usernameKey)

        app.updateServer(URL(string: "https://servidor-a.invalid")!)

        XCTAssertEqual(app.phase, .main, "re-saving the same address is not a switch")
        XCTAssertEqual(Keychain.get(Keychain.usernameKey), "joao")
    }
}
