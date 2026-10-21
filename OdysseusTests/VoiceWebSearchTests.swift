import XCTest
@testable import Odysseus

/// Voice mode sent no web flag at all, so the server kept its web tools off
/// unless the question's words tripped the intent classifier — a question
/// about today was answered from memory. And in plain chat mode the server
/// streams the model's text untouched, so a tool call Gemma wrote into it was
/// shown and spoken.
@MainActor
final class VoiceWebSearchTests: XCTestCase {

    override func setUp() {
        super.setUp(); StubTransport.reset()
        UserDefaults.standard.removeObject(forKey: VoiceConversation.webSearchKey)
    }
    override func tearDown() {
        StubTransport.reset()
        UserDefaults.standard.removeObject(forKey: VoiceConversation.webSearchKey)
        super.tearDown()
    }

    private func fields(_ options: ChatStreamOptions) -> String {
        let api = APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!),
                            protocolClasses: [StubTransport.self])
        let req = ChatStreamClient(api: api).buildRequest(message: "oi", sessionID: "s1", options: options)
        return String(decoding: req.httpBody ?? Data(), as: UTF8.self)
    }

    func testVoiceAllowsWebToolsWithoutForcingAPreSearch() {
        XCTAssertTrue(VoiceConversation.webSearchEnabled, "on by default")
        let body = fields(ChatStreamOptions(allowWebSearch: VoiceConversation.webSearchEnabled))
        XCTAssertTrue(body.contains("name=\"allow_web_search\"\r\n\r\ntrue"), body)
        XCTAssertFalse(body.contains("name=\"use_web\""), "use_web makes the server search before every reply")
    }

    func testWithTheSwitchOffVoiceSendsNoWebFlag() {
        UserDefaults.standard.set(false, forKey: VoiceConversation.webSearchKey)
        let body = fields(ChatStreamOptions(allowWebSearch: VoiceConversation.webSearchEnabled))
        XCTAssertFalse(body.contains("allow_web_search"))
    }

    func testTheChatWebChipStillForcesTheSearch() {
        let body = fields(ChatStreamOptions(webSearch: true))
        XCTAssertTrue(body.contains("name=\"allow_web_search\""))
        XCTAssertTrue(body.contains("name=\"use_web\""))
    }

    func testAToolCallWrittenIntoAChatReplyIsNotShown() async {
        StubTransport.route("/api/chat_stream", .sse([
            #"{"delta": "Vou ver. "}"#,
            #"{"delta": "<tool_call>call:search_web{queries:[\"Flamengo\"]}</tool_call>"}"#,
        ]))
        let app = AppState(protocolClasses: [StubTransport.self])
        let vm = app.makeChatViewModel(session: ChatSession(id: "s1", title: "t"))
        vm.input = "Quem ganhou o último jogo do Flamengo?"
        vm.send()
        for _ in 0..<60 where vm.isStreaming { try? await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(vm.messages.last?.content, "Vou ver. ")
    }

    func testCitationMarkersAreNotSpoken() {
        XCTAssertEqual(SpokenText.strip("O dólar está em 5,01 reais [2]. Veja no Wise [3, 4]."),
                       "O dólar está em 5,01 reais. Veja no Wise.")
    }
}
