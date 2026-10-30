import XCTest
@testable import Odysseus

/// Text colors are derived in `Theme.init` so each one clears WCAG AA on the
/// surfaces it sits on. These recompute the same rule from the catalogue's
/// hex values, so a theme added later cannot slip under 4.5:1 unnoticed.
final class ThemeContrastTests: XCTestCase {

    func testContrastMathMatchesWCAG() {
        XCTAssertEqual(RGB.white.contrast(.black), 21, accuracy: 0.01)
        XCTAssertEqual(RGB(hex: "c6613f").contrast(.white), 4.05, accuracy: 0.01)
    }

    func testEveryCatalogueThemeIsInTheList() {
        XCTAssertEqual(Theme.all.count, 17)
        XCTAssertEqual(Theme.named("nope").id, "claude")
    }
}
