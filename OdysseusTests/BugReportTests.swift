import XCTest
@testable import Odysseus

/// The bug report is the only thing that leaves the device: it must carry the
/// user's words and the last hour, and nothing that identifies the install.
final class BugReportTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("bug-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir); super.tearDown() }

    private func json(_ p: BugReport.Package) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: p.json) as? [String: Any])
    }

    func testTheDescriptionTravelsAndNothingIdentifiesTheInstall() throws {
        let s = DiagnosticsStore(directory: dir)
        s.event("stt.load.ok", ["model": "w-turbo", "ms": "812"])
        let p = BugReport.make(description: "  travou ao trocar de modelo ", store: s)
        let j = try json(p)
        XCTAssertNil(j["installId"])
        XCTAssertEqual((j["report"] as? [String: Any])?["description"] as? String, "travou ao trocar de modelo")
        XCTAssertEqual((j["events"] as? [[String: Any]])?.count, 1)
        XCTAssertTrue(p.subject.hasPrefix("Bug report Odysseus "), p.subject)
        XCTAssertTrue(p.filename.hasPrefix("odysseus-bug-") && p.filename.hasSuffix(".json"), p.filename)
        XCTAssertTrue(p.body.hasPrefix("travou ao trocar de modelo\n"), p.body)
        XCTAssertTrue(p.body.contains(p.filename))
    }

    func testOnlyTheLastHourGoesUnlessItWasQuiet() throws {
        let s = DiagnosticsStore(directory: dir)
        for i in 0..<80 { s.event("e\(i)") }
        let now = try json(BugReport.make(description: "", store: s))
        XCTAssertEqual((now["events"] as? [[String: Any]])?.count, 80, "all 80 are inside the hour")
        let later = try json(BugReport.make(description: "", store: s, now: Date().addingTimeInterval(2 * 3600)))
        let names = (later["events"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        XCTAssertEqual(names?.count, BugReport.minimumEvents, "the hour is empty, so the floor applies")
        XCTAssertEqual(names?.last, "e79")
    }

    func testEachReportHasItsOwnIdAndTheExportHasNone() throws {
        let s = DiagnosticsStore(directory: dir)
        let a = try json(BugReport.make(description: "a", store: s))
        let b = try json(BugReport.make(description: "b", store: s))
        XCTAssertNotEqual((a["report"] as? [String: Any])?["id"] as? String, (b["report"] as? [String: Any])?["id"] as? String)
        let export = try XCTUnwrap(JSONSerialization.jsonObject(with: s.exportJSON()) as? [String: Any])
        XCTAssertNil(export["installId"])
    }

    func testTheLastAbnormalExitIsSpelledOutInTheBody() throws {
        let first = DiagnosticsStore(directory: dir)
        first.startSession(version: "1.11", build: "27")
        first.beginSpan("stt.load", ["model": "w-large", "availMB": "900"])
        // …killed here; the next process reads the same directory.
        let second = DiagnosticsStore(directory: dir)
        second.startSession(version: "1.11", build: "27")
        let p = BugReport.make(description: "", store: second)
        XCTAssertTrue(p.body.contains("w-large"), p.body)
        let j = try json(p)
        XCTAssertEqual(((j["lastAbnormalExit"] as? [String: Any])?["props"] as? [String: String])?["span"], "stt.load")
    }
}
