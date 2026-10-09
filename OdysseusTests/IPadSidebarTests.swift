import XCTest
@testable import Odysseus

/// The iPad sidebar is a split-view column, and a column reports a COMPACT
/// width even on a 13" iPad. Deciding by size class put the iPhone's
/// Espaços bar (and its bottom "Mais" sheet) in the iPad sidebar, over the
/// "Arquivadas" row.
final class IPadSidebarTests: XCTestCase {
    func testThePhoneGetsTheSpacesBar() {
        XCTAssertTrue(SidebarLayout.usesSpacesBar(idiom: .phone, hasSections: true))
        XCTAssertFalse(SidebarLayout.usesSpacesBar(idiom: .phone, hasSections: false), "no sections, no bar")
    }

    func testTheIPadListsTheSpacesInTheSidebar() {
        XCTAssertFalse(SidebarLayout.usesSpacesBar(idiom: .pad, hasSections: true))
    }

    func testTheSpacesStartOpenOnIPadAndClosedOnPhone() {
        XCTAssertTrue(SidebarLayout.spacesExpandedByDefault(idiom: .pad))
        XCTAssertFalse(SidebarLayout.spacesExpandedByDefault(idiom: .phone))
    }

    /// 280 cut "Roteiro de 3 dias em Lisboa" after "Roteiro de 3 dia…".
    func testTheIPadSidebarIsWiderThanTheMacOne() {
        XCTAssertGreaterThan(SidebarLayout.width(idiom: .pad), SidebarLayout.width(idiom: .phone))
        XCTAssertEqual(SidebarLayout.width(idiom: .pad), 320)
    }
}
