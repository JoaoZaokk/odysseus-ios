import XCTest
@testable import Odysseus

/// The privacy manifest ships inside the app and Apple parses it at upload:
/// a malformed file or a stray collected-data type is a rejected build.
final class PrivacyManifestTests: XCTestCase {
    private func manifest() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: AppState.self).url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func testTheManifestParsesAndDeclaresNoCollectedDataAndNoTracking() throws {
        let m = try manifest()
        XCTAssertEqual(m["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((m["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
        XCTAssertEqual((m["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0, "bug reports are user-initiated mail, not collection")
        let apis = try XCTUnwrap(m["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        XCTAssertEqual(Set(apis.compactMap { $0["NSPrivacyAccessedAPIType"] as? String }),
                       ["NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPICategoryDiskSpace"])
    }
}
