import XCTest
import SwiftUI
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

/// The iPhone Duo's outer display reports its system rail as a trailing safe
/// area (measured on iOS 27.1: top 0, bottom 34, trailing 84); a phone held
/// upright has none at the sides.
final class SideRailTests: XCTestCase {
    func testDuoOuterDisplayHasARail() {
        XCTAssertTrue(SideRail.present(EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84)))
    }
    func testUprightPhoneHasNone() {
        XCTAssertFalse(SideRail.present(EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)))
    }
    func testSidewaysPhoneCountsAsRail() {
        XCTAssertTrue(SideRail.present(EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62)))
    }
}
