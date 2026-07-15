import XCTest
@testable import Odysseus

/// The payloads here are copied from the server's own `json.dumps(...)` calls
/// (routes/chat_routes.py, src/agent_loop.py) — if upstream changes a shape,
/// these fail instead of the event silently vanishing into the `default` branch.
final class StreamEventTests: XCTestCase {

    private func event(_ json: String) -> StreamEvent? {
        try? JSONDecoder().decode(StreamEvent.self, from: Data(json.utf8))
    }

    // MARK: - Plain frames still decode

    func testTextDeltaFrame() {
        let e = event(#"{"delta": "olá"}"#)
        XCTAssertEqual(e?.delta, "olá")
        XCTAssertNil(e?.notice)
    }

    func testThinkingDeltaFrame() {
        let e = event(#"{"delta": "hmm", "thinking": true}"#)
        XCTAssertEqual(e?.thinking, true)
    }

    // MARK: - The `data` key collision

    /// `context_trimmed` sends `data` as an object; `web_sources` sends it as an
    /// array. A synthesized decoder throws on the mismatch and the whole frame is
    /// dropped — including its `type`, which is how tokens would go missing.
    func testWebSourcesArrayDataDoesNotBreakDecoding() {
        let e = event(#"{"type": "web_sources", "data": [{"url": "https://x.dev"}]}"#)
        XCTAssertEqual(e?.type, "web_sources")
        XCTAssertNil(e?.trim)
        XCTAssertNil(e?.notice)
    }

    // MARK: - Notices

    func testContextTrimmedReadsNestedData() {
        let e = event(#"""
        {"type": "context_trimmed", "data": {"context_length": 8192, "messages_before": 40,
         "messages_after": 12, "tokens_before": 9000, "tokens_after": 4000}}
        """#)
        XCTAssertEqual(e?.trim?.messagesBefore, 40)
        XCTAssertEqual(e?.trim?.messagesAfter, 12)
        XCTAssertEqual(e?.notice?.kind, .contextTrimmed(removed: 28))
    }

    /// Counts must not go negative if the server ever reports after >= before.
    func testContextTrimmedWithoutUsableCounts() {
        XCTAssertEqual(event(#"{"type": "context_trimmed"}"#)?.notice?.kind,
                       .contextTrimmed(removed: 0))
        XCTAssertEqual(event(#"{"type": "context_trimmed", "data": {"messages_before": 5, "messages_after": 9}}"#)?.notice?.kind,
                       .contextTrimmed(removed: 0))
    }

    func testCompactedReadsTopLevelContextLength() {
        let e = event(#"{"type": "compacted", "context_length": 8192}"#)
        XCTAssertEqual(e?.contextLength, 8192)
        XCTAssertEqual(e?.notice?.kind, .compacted)
    }

    func testBudgetExceeded() {
        let e = event(#"{"type": "budget_exceeded", "limit": 25, "used": 26}"#)
        XCTAssertEqual(e?.notice?.kind, .budgetExceeded(limit: 25, used: 26))
    }

    func testRoundsExhausted() {
        XCTAssertEqual(event(#"{"type": "rounds_exhausted", "rounds": 8}"#)?.notice?.kind,
                       .roundsExhausted(rounds: 8))
    }

    func testLoopBreakerAndIntentNudge() {
        XCTAssertEqual(event(#"{"type": "loop_breaker_triggered", "reason": "loop_breaker_stall", "message": "…", "round": 4}"#)?.notice?.kind,
                       .loopBreaker)
        XCTAssertEqual(event(#"{"type": "intent_nudge_exhausted", "reason": "intent_without_action_nudge_cap", "message": "…", "nudges": 3}"#)?.notice?.kind,
                       .intentNudgeExhausted)
    }

    func testUnrelatedEventsProduceNoNotice() {
        for t in ["tool_start", "agent_step", "doc_update", "plan_update", "fallback"] {
            XCTAssertNil(event("{\"type\": \"\(t)\"}")?.notice, t)
        }
    }

    // MARK: - Errors

    func testErrorFrameMessage() {
        XCTAssertEqual(event(#"{"status": 500, "text": "boom"}"#)?.errorMessage, "boom")
        XCTAssertEqual(event(#"{"error": {"message": "nope"}}"#)?.errorMessage, "nope")
    }
}
