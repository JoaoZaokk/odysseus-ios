import XCTest
@testable import Odysseus

/// `GET /api/history/{sid}` returns `{role, content, metadata}` (core/models.py
/// `ChatMessage.to_dict`), and the server files the reasoning trace into that
/// metadata blob when the stream ends.
final class MessageDecodingTests: XCTestCase {

    private func message(_ json: String) -> Message? {
        try? JSONDecoder().decode(Message.self, from: Data(json.utf8))
    }

    /// Regression: reasoning showed while streaming, then vanished on reopen,
    /// because only a top-level `thinking` was read.
    func testThinkingIsReadFromMetadata() {
        let m = message(#"""
        {"role": "assistant", "content": "42",
         "metadata": {"model": "anthropic/claude", "thinking": "primeiro eu…", "_db_id": "abc"}}
        """#)
        XCTAssertEqual(m?.thinking, "primeiro eu…")
        XCTAssertEqual(m?.model, "anthropic/claude")
        XCTAssertEqual(m?.id, "abc")
    }

    func testTopLevelThinkingWinsOverMetadata() {
        let m = message(#"""
        {"role": "assistant", "content": "x", "thinking": "topo",
         "metadata": {"thinking": "meta"}}
        """#)
        XCTAssertEqual(m?.thinking, "topo")
    }

    func testReasoningAliasStillWorks() {
        XCTAssertEqual(message(#"{"role": "assistant", "content": "x", "reasoning": "r"}"#)?.thinking, "r")
    }

    func testNoThinkingAnywhere() {
        XCTAssertNil(message(#"{"role": "assistant", "content": "x", "metadata": {"model": "m"}}"#)?.thinking)
    }

    /// Plain chat mode saves the reply as the model wrote it, so a tool call
    /// cut from the stream came back every time the chat was reopened.
    func testAToolCallSavedInAReplyIsNotShownOnReopen() {
        let m = message(#"{"role": "assistant", "content": "Vou ver. <tool_call>call:search_web{queries:[\"Flamengo\"]}</tool_call>"}"#)
        XCTAssertEqual(m?.content, "Vou ver.")
    }

    func testAReplyThatWasOnlyACallReadsAsNoReply() {
        let m = message(#"{"role": "assistant", "content": "<tool_call>call:search_web{queries:[\"x\"]}</tool_call>"}"#)
        XCTAssertEqual(m?.content, "_\(L("(sem resposta)"))_")
    }

    func testTheUsersOwnWordsAreNeverFiltered() {
        let m = message(#"{"role": "user", "content": "call:search_web{\"q\": 1}"}"#)
        XCTAssertEqual(m?.content, #"call:search_web{"q": 1}"#)
    }

    func testMultimodalContentPartsAreFlattened() {
        let m = message(#"""
        {"role": "user", "content": [{"type": "text", "text": "olha"},
                                     {"type": "image_url", "image_url": {"url": "u"}}]}
        """#)
        XCTAssertEqual(m?.content, "olha")
        XCTAssertEqual(m?.role, .user)
    }
}
