import XCTest
@testable import Odysseus

/// Breadcrumbs that survive a SIGKILL: an open span found on the next launch
/// is the only evidence a jetsam leaves.
final class DiagnosticsStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir); super.tearDown() }

    func testEventsAreAppendedAndReadBackInOrder() {
        let s = DiagnosticsStore(directory: dir)
        s.event("a", ["x": "1"])
        s.event("b")
        let got = s.recentEvents()
        XCTAssertEqual(got.map(\.name), ["a", "b"])
        XCTAssertEqual(got[0].props["x"], "1")
        s.drop(upTo: got[0].ts)
        XCTAssertEqual(s.recentEvents().map(\.name), ["b"])
    }

    func testOpenSpanBecomesASuspectedDeathOnTheNextLaunch() {
        let first = DiagnosticsStore(directory: dir)
        first.startSession(version: "1.11", build: "27")
        first.beginSpan("stt.load", ["model": "w-turbo", "availMB": "412"])
        // …the process is killed here; a new store reads the same directory.
        let second = DiagnosticsStore(directory: dir)
        XCTAssertEqual(second.openSpans()["stt.load"]?["model"], "w-turbo")
        second.startSession(version: "1.11", build: "27")
        let death = second.lastSuspectedDeath()
        XCTAssertEqual(death?.name, "death.suspected")
        XCTAssertEqual(death?.props["span"], "stt.load")
        XCTAssertEqual(death?.props["model"], "w-turbo")
        XCTAssertEqual(death?.props["availMB"], "412")
        XCTAssertTrue(second.openSpans().isEmpty, "the leftover span is consumed")
    }

    func testCleanSessionEndLeavesNoAbnormalMark() {
        let first = DiagnosticsStore(directory: dir)
        first.startSession(version: "1", build: "1")
        first.beginSpan("stt.decode", ["model": "m"])
        first.endSpan("stt.decode", ["chars": "12"])
        first.endSession()
        let second = DiagnosticsStore(directory: dir)
        second.startSession(version: "1", build: "1")
        XCTAssertNil(second.lastSuspectedDeath())
        let ok = second.recentEvents().first { $0.name == "stt.decode.ok" }
        XCTAssertNotNil(ok?.props["ms"])
        XCTAssertEqual(ok?.props["chars"], "12")
    }

    func testAbnormalEndWithoutSpanIsStillRecorded() {
        let first = DiagnosticsStore(directory: dir)
        first.startSession(version: "1", build: "1")
        let second = DiagnosticsStore(directory: dir)
        second.startSession(version: "1", build: "1")
        XCTAssertEqual(second.lastSuspectedDeath()?.name, "session.abnormal_end")
    }

    func testEngineLogTailIsKept() {
        let s = DiagnosticsStore(directory: dir)
        for i in 0..<500 { s.appendEngineLog("line \(i)") }
        let tail = s.engineLogTail(3)
        XCTAssertEqual(tail, ["line 497", "line 498", "line 499"])
        XCTAssertFalse(s.exportJSON().isEmpty)
    }
}
