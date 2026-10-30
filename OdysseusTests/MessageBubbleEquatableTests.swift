import XCTest
@testable import Odysseus

/// The transcript draws bubbles with `.equatable()`: a token must redraw the
/// bubble it lands in and leave the rest of a long chat alone.
final class MessageBubbleEquatableTests: XCTestCase {
    private let msg = Message(id: "m1", role: .assistant, content: "Olá")

    func testSameMessageIsEqualWhateverTheClosure() {
        let a = MessageBubble(message: msg, attachmentURL: { _ in nil })
        let b = MessageBubble(message: msg, attachmentURL: { URL(string: "https://example.com/\($0)") })
        XCTAssertEqual(a, b)
    }

    func testNewTokenRedraws() {
        var grown = msg
        grown.content += " mundo"
        XCTAssertNotEqual(MessageBubble(message: msg), MessageBubble(message: grown))
    }

    func testStreamingFlagRedraws() {
        XCTAssertNotEqual(MessageBubble(message: msg, isStreaming: true),
                          MessageBubble(message: msg, isStreaming: false))
    }

    func testThinkingRedraws() {
        var thought = msg
        thought.thinking = "pensando"
        XCTAssertNotEqual(MessageBubble(message: msg), MessageBubble(message: thought))
    }
}
