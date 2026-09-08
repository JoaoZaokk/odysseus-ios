import XCTest
@testable import Odysseus

/// The rating prompt, in two layers: the rule on its own, and the signal
/// that feeds it — a reply that streamed cleanly — driven through the
/// transport seam with an SSE body. `StubTransport.Reply.sse` was written
/// for exactly this and had no caller until now.
@MainActor
final class ReviewGateTests: XCTestCase {

    private var defaults: UserDefaults!
    private let day: TimeInterval = 86_400

    override func setUp() {
        super.setUp()
        StubTransport.reset()
        ReviewGate.launchIsPoisoned = false
        defaults = UserDefaults(suiteName: "review.tests")!
        defaults.removePersistentDomain(forName: "review.tests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "review.tests")
        ReviewGate.launchIsPoisoned = false
        StubTransport.reset()
        super.tearDown()
    }

    /// A gate seeded ten days ago, on version 1.9.
    private func gate(daysSinceFirstLaunch: Double = 10, version: String = "1.9") -> ReviewGate {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        ReviewGate.seedFirstLaunchIfNeeded(defaults, now: now.addingTimeInterval(-daysSinceFirstLaunch * day))
        return ReviewGate(defaults: defaults, now: { now }, version: version)
    }

    // MARK: - The rule

    func testTheFifthCleanReplyAsksAndTheSixthDoesNot() {
        let g = gate()
        for _ in 1...4 { XCTAssertFalse(g.recordSuccessfulReply(sessionCount: 3)) }
        XCTAssertTrue(g.recordSuccessfulReply(sessionCount: 3), "the fifth clean reply is the moment")
        XCTAssertFalse(g.recordSuccessfulReply(sessionCount: 3), "once per version")
        XCTAssertEqual(defaults.string(forKey: ReviewGate.askedVersionKey), "1.9")
    }

    func testTooFewConversationsNeverAsks() {
        let g = gate()
        for _ in 1...8 { XCTAssertFalse(g.recordSuccessfulReply(sessionCount: 2)) }
    }

    func testTooEarlyNeverAsks() {
        let g = gate(daysSinceFirstLaunch: 1)
        for _ in 1...8 { XCTAssertFalse(g.recordSuccessfulReply(sessionCount: 5)) }
    }

    func testAnUnseededClockNeverAsks() {
        // No first-launch timestamp means the build carrying the gate has
        // never run its launch hook — day zero must not count as three days.
        let g = ReviewGate(defaults: defaults, now: Date.init, version: "1.9")
        for _ in 1...8 { XCTAssertFalse(g.recordSuccessfulReply(sessionCount: 5)) }
    }

    func testANewVersionEarnsItsOwnPromptFromScratch() {
        var g = gate()
        for _ in 1...5 { _ = g.recordSuccessfulReply(sessionCount: 3) }
        g.version = "2.0"
        for _ in 1...4 { XCTAssertFalse(g.recordSuccessfulReply(sessionCount: 3), "the counter restarted at the ask") }
        XCTAssertTrue(g.recordSuccessfulReply(sessionCount: 3))
    }

    func testAPoisonedLaunchNeverAsksButStillCounts() {
        let g = gate()
        ReviewGate.launchIsPoisoned = true
        for _ in 1...6 { XCTAssertFalse(g.recordSuccessfulReply(sessionCount: 3)) }
        XCTAssertEqual(defaults.integer(forKey: ReviewGate.repliesKey), 6, "the replies were real; only this launch is out")
    }

    func testSeedingIsIdempotent() {
        let first = Date(timeIntervalSince1970: 1_000)
        ReviewGate.seedFirstLaunchIfNeeded(defaults, now: first)
        ReviewGate.seedFirstLaunchIfNeeded(defaults, now: first.addingTimeInterval(day))
        XCTAssertEqual(defaults.double(forKey: ReviewGate.firstLaunchKey), 1_000)
    }

    // MARK: - The signal, through the seam

    private func streamedViewModel(_ frames: [String]) async -> (ChatViewModel, Bool) {
        StubTransport.route("/api/chat_stream", .sse(frames))
        let app = AppState(protocolClasses: [StubTransport.self])
        let vm = app.makeChatViewModel(session: ChatSession(id: "s1", title: "t"))
        var fired = false
        vm.onReplyCompleted = { fired = true }
        vm.input = "oi"
        vm.send()
        for _ in 0..<40 where vm.isStreaming { try? await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertFalse(vm.isStreaming, "the stream never finished")
        return (vm, fired)
    }

    func testACleanReplyFiresTheSignal() async {
        let (vm, fired) = await streamedViewModel([#"{"delta": "Olá"}"#, #"{"delta": " mundo"}"#, "[DONE]"])
        XCTAssertTrue(fired)
        XCTAssertFalse(ReviewGate.launchIsPoisoned)
        XCTAssertEqual(vm.messages.last?.content, "Olá mundo")
    }

    func testAnErrorFrameAfterTextIsNotASuccessAndPoisonsTheLaunch() async {
        // The loop finishes normally on an error frame — nothing throws — so
        // "the do-block completed" would have counted this as a clean reply.
        let (vm, fired) = await streamedViewModel([#"{"delta": "Ol"}"#, #"{"status": 500, "detail": "boom"}"#])
        XCTAssertFalse(fired)
        XCTAssertTrue(ReviewGate.launchIsPoisoned)
        XCTAssertEqual(vm.messages.last?.content, "Ol", "the text that arrived is kept")
    }

    func testAnEmptyReplyIsNotASuccess() async {
        let (_, fired) = await streamedViewModel(["[DONE]"])
        XCTAssertFalse(fired)
    }

    func testA401OnTheStreamPoisonsTheLaunch() async {
        StubTransport.route("/api/chat_stream", .json(#"{"detail": "expired"}"#, status: 401))
        let app = AppState(protocolClasses: [StubTransport.self])
        app.phase = .main
        let vm = app.makeChatViewModel(session: ChatSession(id: "s1", title: "t"))
        vm.input = "oi"
        vm.send()
        for _ in 0..<40 where vm.isStreaming { try? await Task.sleep(nanoseconds: 50_000_000) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(ReviewGate.launchIsPoisoned)
        XCTAssertEqual(app.phase, .login)
    }
}
