import XCTest
@testable import Odysseus

/// Code blocks the web draws (Mermaid, SVG, HTML) instead of printing. Ported
/// from the Open WebUI app 1.12.
final class RichBlockTests: XCTestCase {

    func testCodeBlocksTheChatDrawsAreRecognised() {
        XCTAssertEqual(RichBlock(language: "mermaid"), .mermaid)
        XCTAssertEqual(RichBlock(language: "SVG"), .svg)
        XCTAssertEqual(RichBlock(language: "html"), .html)
        XCTAssertNil(RichBlock(language: "python"))
        XCTAssertNil(RichBlock(language: nil))
    }

    func testTheMermaidPageIsBundledAndEscapesTheCode() throws {
        XCTAssertNotNil(RichBlock.resourceBase, "mermaid.min.js is not in the app bundle")
        let page = RichBlock.page(.mermaid, code: "graph TD; A-->B<script>", theme: Theme.named("claude"))
        XCTAssertTrue(page.contains("A--&gt;B&lt;script&gt;"), "the diagram code must not run as HTML")
        XCTAssertTrue(page.contains("src=\"mermaid.min.js\""))
    }

    /// A diagram or a picture never reaches the network; the HTML preview is
    /// the model's own page and stays as the web shows it.
    func testDrawnPagesCannotReachTheNetwork() {
        let theme = Theme.named("claude")
        for kind in [RichBlock.mermaid, .svg] {
            XCTAssertTrue(RichBlock.page(kind, code: "<svg/>", theme: theme).contains("default-src 'none'"), "\(kind)")
        }
        XCTAssertFalse(RichBlock.page(.html, code: "<p>oi</p>", theme: theme).contains("Content-Security-Policy"))
    }

    /// Charts take the theme's accent first and stay apart from it, in all 17.
    func testChartColoursFollowTheTheme() {
        for t in Theme.all {
            let p = RichBlock.palette(for: t)
            XCTAssertEqual(p.first, "#" + t.hex.accent, t.id)
            XCTAssertEqual(Set(p).count, p.count, "\(t.id): two slices share a colour")
            XCTAssertGreaterThanOrEqual(p.count, 6, t.id)
        }
        let vars = RichBlock.chartVariables(Theme.named("claude"))
        XCTAssertTrue(vars.contains("\"pieTitleTextColor\":\"#f5f4f0\""), vars)
        XCTAssertTrue(vars.contains("\"plotColorPalette\":\"#c6613f"), vars)
    }

    /// A fragment opens as a phone page; a whole document is left as written.
    func testThePreviewIsAPhonePage() {
        let frag = RichBlock.preview("<h1>Olá</h1>")
        XCTAssertTrue(frag.contains("width=device-width"))
        XCTAssertTrue(frag.contains("<h1>Olá</h1>"))
        let doc = "<html><body>x</body></html>"
        XCTAssertEqual(RichBlock.preview(doc), doc)
    }
}
