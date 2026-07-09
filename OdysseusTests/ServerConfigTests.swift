import XCTest
@testable import Odysseus

final class ServerConfigTests: XCTestCase {

    // MARK: isLocalHost — genuine local hosts

    func testLoopbackAndLocalNamesAreLocal() {
        XCTAssertTrue(ServerConfig.isLocalHost("localhost"))
        XCTAssertTrue(ServerConfig.isLocalHost("127.0.0.1"))
        XCTAssertTrue(ServerConfig.isLocalHost("0.0.0.0"))
        XCTAssertTrue(ServerConfig.isLocalHost("my-server.local"))
    }

    func testRFC1918RangesAreLocal() {
        XCTAssertTrue(ServerConfig.isLocalHost("10.0.0.5"))
        XCTAssertTrue(ServerConfig.isLocalHost("192.168.1.10"))
        XCTAssertTrue(ServerConfig.isLocalHost("172.16.0.1"))
        XCTAssertTrue(ServerConfig.isLocalHost("172.31.255.254"))
    }

    // MARK: isLocalHost — spoofing attempts must stay public

    func testPublicHostsAreNotLocal() {
        XCTAssertFalse(ServerConfig.isLocalHost("8.8.8.8"))
        XCTAssertFalse(ServerConfig.isLocalHost("example.com"))
        // The classic prefix-spoof: a DNS name starting with "10." is NOT an IP.
        XCTAssertFalse(ServerConfig.isLocalHost("10.evil.com"))
        XCTAssertFalse(ServerConfig.isLocalHost("192.168.evil.com"))
        // 172.32.x is outside 172.16.0.0/12.
        XCTAssertFalse(ServerConfig.isLocalHost("172.32.0.1"))
    }

    // MARK: allowed schemes

    func testOnlyHTTPSchemesAllowed() {
        XCTAssertEqual(ServerConfig.allowedSchemes, ["http", "https"])
    }
}
