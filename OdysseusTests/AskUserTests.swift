import XCTest
@testable import Odysseus

/// The 1.8 German review — "die Rückfragen im Chat nicht angezeigt werden".
///
/// `ask_user` ENDS the agent's turn: the server sends the question and no reply
/// text, then waits for the answer. Every frame here is copied from the
/// server's own `json.dumps` (src/agent_loop.py, src/tool_approvals.py,
/// routes/chat_routes.py), so an upstream shape change fails a test instead of
/// silently falling into the stream loop's `default` branch again.
@MainActor
final class AskUserTests: XCTestCase {

    override func setUp() { super.setUp(); StubTransport.reset() }
    override func tearDown() { StubTransport.reset(); super.tearDown() }

    /// One SSE frame is one line — the loop splits on newlines, so these stay flat.
    private let askFrame = #"{"type": "ask_user", "data": {"question": "Qual banco?", "multi": false, "options": [{"label": "Postgres", "description": "Já está de pé"}, {"label": "SQLite"}]}}"#

    private func streamed(_ frames: [String]) async -> ChatViewModel {
        StubTransport.route("/api/chat_stream", .sse(frames))
        let app = AppState(protocolClasses: [StubTransport.self])
        let vm = app.makeChatViewModel(session: ChatSession(id: "s1", title: "t"))
        vm.input = "monta o banco"
        vm.send()
        await settle(vm)
        return vm
    }

    private func settle(_ vm: ChatViewModel) async {
        for _ in 0..<40 where vm.isStreaming { try? await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertFalse(vm.isStreaming, "the stream never finished")
    }

    /// chat_stream is multipart, not urlencoded — the fields have to be read out
    /// of the part headers.
    private func field(_ name: String) -> String? {
        let raw = String(decoding: StubTransport.sentBodies["/api/chat_stream"] ?? Data(), as: UTF8.self)
        guard let head = raw.range(of: "name=\"\(name)\"\r\n\r\n") else { return nil }
        let rest = raw[head.upperBound...]
        guard let end = rest.range(of: "\r\n--") else { return nil }
        return String(rest[..<end.lowerBound])
    }

    // MARK: - The frame

    func testAskUserFrameDecodes() {
        let e = try? JSONDecoder().decode(StreamEvent.self, from: Data(askFrame.utf8))
        XCTAssertEqual(e?.type, "ask_user")
        XCTAssertEqual(e?.ask?.question, "Qual banco?")
        XCTAssertEqual(e?.ask?.options.map(\.label), ["Postgres", "SQLite"])
        XCTAssertEqual(e?.ask?.options.first?.description, "Já está de pé")
        XCTAssertEqual(e?.ask?.multi, false)
        XCTAssertFalse(e?.ask?.isApproval ?? true)
        XCTAssertTrue(e?.ask?.isRenderable ?? false)
        // `data` is shared with context_trimmed, whose fields are all optional —
        // it decodes as an empty TrimData and must not be read as a notice.
        XCTAssertNil(e?.trim?.messagesBefore)
        XCTAssertNil(e?.notice)
    }

    /// The tool itself refuses fewer than two options; a card that slips through
    /// anyway would be a dead end on screen.
    func testMalformedCardIsNotRenderable() {
        let one = #"{"type": "ask_user", "data": {"question": "Q", "options": [{"label": "só uma"}]}}"#
        let none = #"{"type": "ask_user", "data": {"question": "", "options": [{"label": "a"}, {"label": "b"}]}}"#
        for raw in [one, none] {
            let e = try? JSONDecoder().decode(StreamEvent.self, from: Data(raw.utf8))
            XCTAssertFalse(e?.ask?.isRenderable ?? true, raw)
        }
    }

    /// A consumed approval is history. The web drops it and so do we.
    func testResolvedCardIsNotRenderable() {
        let raw = #"""
        {"type": "ask_user", "data": {"kind": "tool_approval", "approval_id": "a1",
          "question": "Allow?", "resolved": "approve",
          "options": [{"label": "Allow", "value": "approve"}, {"label": "Deny", "value": "deny"}]}}
        """#
        let e = try? JSONDecoder().decode(StreamEvent.self, from: Data(raw.utf8))
        XCTAssertFalse(e?.ask?.isRenderable ?? true)
    }

    // MARK: - A turn that ends on a question

    func testQuestionSurvivesTheStreamAndLeavesNoEmptyBubble() async {
        let vm = await streamed([askFrame, "[DONE]"])
        XCTAssertEqual(vm.pendingAsk?.question, "Qual banco?")
        XCTAssertEqual(vm.messages.count, 1, "only the user's message; the card is the reply")
        XCTAssertEqual(vm.messages.last?.role, .user)
    }

    /// Without the card this was the whole bug: an ask_user turn looked exactly
    /// like a model that answered nothing.
    func testWithoutAQuestionAnEmptyTurnStillReadsAsNoReply() async {
        let vm = await streamed(["[DONE]"])
        XCTAssertNil(vm.pendingAsk)
        XCTAssertEqual(vm.messages.last?.role, .assistant)
        XCTAssertTrue(vm.messages.last?.content.contains("sem resposta") ?? false)
    }

    /// Text and a question can share a turn — the round's prose is a real reply.
    func testTextBeforeTheQuestionIsKept() async {
        let vm = await streamed([#"{"delta": "Preciso saber uma coisa."}"#, askFrame, "[DONE]"])
        XCTAssertEqual(vm.messages.last?.content, "Preciso saber uma coisa.")
        XCTAssertNotNil(vm.pendingAsk)
    }

    // MARK: - Answering

    func testTappingAnOptionSendsItAsTheNextMessage() async {
        let vm = await streamed([askFrame, "[DONE]"])
        guard let ask = vm.pendingAsk else { return XCTFail("no card") }
        StubTransport.route("/api/chat_stream", .sse([#"{"delta": "feito"}"#, "[DONE]"]))
        vm.answer(ask, with: ["Postgres"])
        await settle(vm)
        XCTAssertNil(vm.pendingAsk)
        XCTAssertEqual(field("message"), "Postgres")
        XCTAssertEqual(vm.messages.map(\.content), ["monta o banco", "Postgres", "feito"])
    }

    func testMultiSelectSendsOneMessageWithEveryPick() async {
        let multi = #"{"type": "ask_user", "data": {"question": "Quais?", "multi": true, "options": [{"label": "A"}, {"label": "B"}, {"label": "C"}]}}"#
        let vm = await streamed([multi, "[DONE]"])
        guard let ask = vm.pendingAsk else { return XCTFail("no card") }
        XCTAssertTrue(ask.multi)
        StubTransport.route("/api/chat_stream", .sse(["[DONE]"]))
        vm.answer(ask, with: ["A", "C"])
        await settle(vm)
        XCTAssertEqual(field("message"), "A, C")
    }

    /// The web removes the card as soon as a user message lands, clicked or not.
    func testTypingAnAnswerClearsTheCard() async {
        let vm = await streamed([askFrame, "[DONE]"])
        XCTAssertNotNil(vm.pendingAsk)
        StubTransport.route("/api/chat_stream", .sse(["[DONE]"]))
        vm.input = "nenhum dos dois"
        vm.send()
        await settle(vm)
        XCTAssertNil(vm.pendingAsk)
    }

    func testDismissJustClosesTheCard() async {
        let vm = await streamed([askFrame, "[DONE]"])
        vm.dismissAsk()
        XCTAssertNil(vm.pendingAsk)
        XCTAssertFalse(StubTransport.seen.filter { $0 == "/api/chat_stream" }.count > 1,
                       "dismissing is not an answer")
    }

    // MARK: - Tool approval

    private let approvalFrame = #"{"type": "ask_user", "data": {"kind": "tool_approval", "approval_id": "ap-1", "session_id": "s1", "question": "Allow this task to continue?", "description": "Untrusted context influenced this run.", "action": {"tool": "bash", "content": "rm -rf build", "effects": ["filesystem"]}, "options": [{"label": "Allow for this task", "value": "approve_task"}, {"label": "Deny", "value": "deny"}]}}"#

    func testApprovalIsRecognizedAndCarriesItsAction() async {
        let vm = await streamed([approvalFrame, "[DONE]"])
        guard let ask = vm.pendingAsk else { return XCTFail("no card") }
        XCTAssertTrue(ask.isApproval)
        XCTAssertEqual(ask.approvalID, "ap-1")
        XCTAssertEqual(ask.action?.tool, "bash")
        XCTAssertEqual(ask.action?.content, "rm -rf build")
        XCTAssertEqual(ask.options.map(\.value), ["approve_task", "deny"])
    }

    /// An approval answer is a control-plane continuation: the sealed action is
    /// replayed server-side, so the turn carries no user message and none is
    /// shown. Sending the label as text instead would just start a new turn and
    /// leave the approval pending forever.
    func testApprovingPostsTheDecisionAndAddsNoUserMessage() async {
        let vm = await streamed([approvalFrame, "[DONE]"])
        guard let ask = vm.pendingAsk, let allow = ask.options.first else { return XCTFail("no card") }
        StubTransport.route("/api/chat_stream", .sse([#"{"delta": "pronto"}"#, "[DONE]"]))
        vm.decide(ask, option: allow)
        await settle(vm)
        XCTAssertEqual(field("tool_approval_id"), "ap-1")
        XCTAssertEqual(field("tool_approval_decision"), "approve_task")
        XCTAssertEqual(field("message"), "")
        XCTAssertEqual(vm.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(vm.messages.last?.content, "pronto")
        XCTAssertNil(vm.pendingAsk)
    }

    /// Denial answers with one frame and no text at all.
    func testDenyingExplainsWhyNothingCameBack() async {
        let vm = await streamed([approvalFrame, "[DONE]"])
        guard let ask = vm.pendingAsk, let deny = ask.options.last else { return XCTFail("no card") }
        StubTransport.route("/api/chat_stream",
                            .sse([#"{"type": "tool_approval_resolved", "decision": "deny"}"#]))
        vm.decide(ask, option: deny)
        await settle(vm)
        XCTAssertEqual(field("tool_approval_decision"), "deny")
        XCTAssertEqual(vm.notices.map(\.kind), [.approvalDenied])
        XCTAssertEqual(vm.messages.count, 1, "no empty assistant bubble under the notice")
    }

    // MARK: - Reopening the chat

    private func history(_ raw: String) async -> ChatViewModel {
        StubTransport.route("/api/history/s1", .json(raw))
        let app = AppState(protocolClasses: [StubTransport.self])
        let vm = app.makeChatViewModel(session: ChatSession(id: "s1", title: "t"))
        vm.loadHistoryIfNeeded()
        for _ in 0..<40 where vm.isLoadingHistory { try? await Task.sleep(nanoseconds: 50_000_000) }
        return vm
    }

    /// The card is durable server-side (`metadata.tool_events[].ask_user`), which
    /// is the only reason a reopened chat can still be answered.
    func testAnUnansweredQuestionComesBackWithTheHistory() async {
        let vm = await history(#"""
        {"model": "m", "history": [
          {"role": "user", "content": "monta o banco"},
          {"role": "assistant", "content": "", "metadata": {"tool_events": [
            {"ask_user": {"question": "Qual banco?", "options": [{"label": "Postgres"}, {"label": "SQLite"}]}}]}}]}
        """#)
        XCTAssertEqual(vm.pendingAsk?.question, "Qual banco?")
        XCTAssertEqual(vm.messages.last?.askUser?.options.count, 2)
    }

    /// Anything sent after the card already answered it.
    func testAnAnsweredQuestionDoesNotComeBack() async {
        let vm = await history(#"""
        {"model": "m", "history": [
          {"role": "assistant", "content": "", "metadata": {"tool_events": [
            {"ask_user": {"question": "Qual banco?", "options": [{"label": "Postgres"}, {"label": "SQLite"}]}}]}},
          {"role": "user", "content": "Postgres"},
          {"role": "assistant", "content": "feito"}]}
        """#)
        XCTAssertNil(vm.pendingAsk)
    }

    func testAConsumedApprovalDoesNotComeBack() async {
        let vm = await history(#"""
        {"model": "m", "history": [
          {"role": "assistant", "content": "", "metadata": {"tool_events": [
            {"ask_user": {"kind": "tool_approval", "approval_id": "ap-1", "resolved": "approve",
              "question": "Allow?", "options": [{"label": "Allow", "value": "approve"},
                                                {"label": "Deny", "value": "deny"}]}}]}}]}
        """#)
        XCTAssertNil(vm.pendingAsk)
    }

    /// Tool events without a question are the normal case — every other tool.
    func testOrdinaryToolEventsCarryNoCard() async {
        let vm = await history(#"""
        {"model": "m", "history": [
          {"role": "assistant", "content": "ok", "metadata": {"tool_events": [
            {"tool": "bash", "output": "hi"}]}}]}
        """#)
        XCTAssertNil(vm.pendingAsk)
        XCTAssertEqual(vm.messages.last?.content, "ok")
    }
}
