import XCTest
@testable import Odysseus

/// 2FA from the phone. 1.8 read the status in two places and could change it
/// in neither; the server's setup/confirm/disable are plain user routes.
@MainActor
final class TwoFactorTests: XCTestCase {

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

    // A 1×1 PNG, the way the server ships the QR: a data URL.
    private let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="

    func testSetupDecodesTheDataURLIntoPNGBytes() async throws {
        StubTransport.route("/api/auth/2fa/setup",
                            .json(#"{"secret": "JBSWY3DPEHPK3PXP", "uri": "otpauth://totp/x", "qr_code": "data:image/png;base64,\#(png)"}"#))
        let s = try await client().twoFASetup()
        XCTAssertEqual(StubTransport.methods["/api/auth/2fa/setup"], "POST")
        XCTAssertEqual(s.secret, "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(s.qrPNG?.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), "PNG magic")
    }

    func testConfirmPostsTheCodeAndReturnsTheBackupCodes() async throws {
        StubTransport.route("/api/auth/2fa/confirm", .json(#"{"ok": true, "backup_codes": ["aaaa-1111", "bbbb-2222"]}"#))
        let codes = try await client().twoFAConfirm(code: "123456")
        XCTAssertEqual(json("/api/auth/2fa/confirm")["code"] as? String, "123456")
        XCTAssertEqual(codes, ["aaaa-1111", "bbbb-2222"])
    }

    func testDisablePostsThePassword() async throws {
        StubTransport.route("/api/auth/2fa/disable", .json(#"{"ok": true}"#))
        try await client().twoFADisable(password: "hunter2")
        XCTAssertEqual(json("/api/auth/2fa/disable")["password"] as? String, "hunter2")
    }

    // MARK: - The screen's steps

    func testTheFlowGoesOffEnrollingBackupCodes() async {
        StubTransport.route("/api/auth/2fa/status", .json(#"{"enabled": false}"#))
        StubTransport.route("/api/auth/2fa/setup", .json(#"{"secret": "S", "uri": "u", "qr_code": "data:image/png;base64,\#(png)"}"#))
        StubTransport.route("/api/auth/2fa/confirm", .json(#"{"ok": true, "backup_codes": ["c1"]}"#))
        let vm = TwoFactorVM(api: client())
        await vm.load()
        XCTAssertEqual(vm.step, .off)
        await vm.begin()
        XCTAssertEqual(vm.step, .enrolling)
        XCTAssertEqual(vm.secret, "S")
        XCTAssertNotNil(vm.qr)
        vm.code = "123456"
        await vm.confirm()
        XCTAssertEqual(vm.step, .backupCodes)
        XCTAssertEqual(vm.backupCodes, ["c1"])
    }

    func testAWrongCodeStaysOnTheEnrollStepAndSaysWhy() async {
        StubTransport.route("/api/auth/2fa/setup", .json(#"{"secret": "S", "uri": "u", "qr_code": ""}"#))
        StubTransport.route("/api/auth/2fa/confirm", .json(#"{"detail": "Invalid code — try again"}"#, status: 400))
        let vm = TwoFactorVM(api: client())
        await vm.begin()
        vm.code = "000000"
        await vm.confirm()
        XCTAssertEqual(vm.step, .enrolling, "the QR must stay on screen for another try")
        XCTAssertEqual(vm.note, "Falha: Invalid code — try again")
    }

    func testDisablingWithTheWrongPasswordKeepsItOn() async {
        StubTransport.route("/api/auth/2fa/status", .json(#"{"enabled": true}"#))
        StubTransport.route("/api/auth/2fa/disable", .json(#"{"detail": "Invalid password"}"#, status: 400))
        let vm = TwoFactorVM(api: client())
        await vm.load()
        XCTAssertEqual(vm.step, .on)
        vm.password = "nope"
        await vm.disable()
        XCTAssertEqual(vm.step, .on)
        XCTAssertEqual(vm.note, "Falha: Invalid password")
        XCTAssertEqual(vm.password, "nope", "not cleared on failure — the user retypes one character, not all")
    }
}
