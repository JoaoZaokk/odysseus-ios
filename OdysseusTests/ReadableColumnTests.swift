import XCTest
@testable import Odysseus

/// iPad: a screen's content sits in a centred reading column instead of
/// running 1000+ pt edge to edge (Tasks stretched its two buttons across the
/// screen).
final class ReadableColumnTests: XCTestCase {
    func testCompactWidthIsNotCapped() {
        // iPhone, iPhone in landscape, iPad slide-over: all compact.
        XCTAssertEqual(Spacing.readableMaxWidth(regular: false), .infinity)
    }

    func testRegularWidthStopsAtTheReadingColumn() {
        XCTAssertEqual(Spacing.readableMaxWidth(regular: true), Spacing.readableWidth)
    }

    func testTheChatColumnAndTheListColumnAreTheSameWidth() {
        XCTAssertEqual(Spacing.readableWidth, 720)
    }
}
