import XCTest
#if os(iOS)
import UIKit
#endif
@testable import Odysseus

/// `setAlternateIconName` fails silently-ish at runtime when a name is missing
/// from `CFBundleAlternateIcons` or its file is not in the bundle — and the only
/// symptom is an icon that never changes. Both halves are checked here.
final class AppIconTests: XCTestCase {
    private var bundle: Bundle { Bundle(for: AppState.self) }

    private func declaredAlternates() throws -> [String: Any] {
        let icons = try XCTUnwrap(bundle.infoDictionary?["CFBundleIcons"] as? [String: Any])
        return try XCTUnwrap(icons["CFBundleAlternateIcons"] as? [String: Any])
    }

    func testTheSailIsThePrimaryIconAndEveryOtherChoiceIsDeclaredAsAnAlternate() throws {
        XCTAssertNil(AppIcon.odysseus.alternateName, "the sail is the asset-catalog icon")
        let declared = Set(try declaredAlternates().keys)
        let wanted = Set(AppIcon.allCases.compactMap(\.alternateName))
        XCTAssertEqual(wanted, declared, "project.yml and AppIcon must name the same icons")
    }

    func testEveryDeclaredAlternateShipsItsFiles() throws {
        for (name, entry) in try declaredAlternates() {
            let files = try XCTUnwrap((entry as? [String: Any])?["CFBundleIconFiles"] as? [String])
            XCTAssertEqual(files, [name])
            for scale in ["@2x", "@3x"] {
                XCTAssertNotNil(bundle.url(forResource: name + scale, withExtension: "png"),
                                "\(name)\(scale).png is not in the bundle")
            }
        }
    }

    #if os(iOS)
    func testEveryChoiceHasAPreviewThePickerCanDraw() {
        for icon in AppIcon.allCases {
            XCTAssertNotNil(UIImage(named: icon.previewImageName, in: bundle, compatibleWith: nil),
                            "no preview image for \(icon.rawValue)")
        }
    }
    #endif

    func testTheSavedChoiceSurvivesAndAnUnknownOneFallsBackToTheSail() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: AppIconManager.storageKey)
        defer { defaults.set(previous, forKey: AppIconManager.storageKey) }

        defaults.set("gemini", forKey: AppIconManager.storageKey)
        XCTAssertEqual(AppIconManager.selected, .gemini)
        defaults.set("a-theme-that-was-renamed", forKey: AppIconManager.storageKey)
        XCTAssertEqual(AppIconManager.selected, .odysseus)
    }
}
