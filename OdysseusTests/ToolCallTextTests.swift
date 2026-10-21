import XCTest
@testable import Odysseus

/// A model with no tool to call — or whose server failed to parse its call —
/// writes the call out as text. Reported against the Open WebUI client with
/// Gemma 4 through LM Studio in voice mode; the Odysseus server strips these in
/// agent mode but not in plain chat mode: `<tool_call>call:search_web{queries:[...]}</tool_call>` was
/// shown, spoken and saved as the answer.
final class ToolCallTextTests: XCTestCase {

    /// Feeds `text` in pieces of `size` characters, the way a stream does.
    private func filtered(_ text: String, size: Int) -> (shown: String, calls: [ToolCall]) {
        var f = ToolCallFilter()
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            let j = text.index(i, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            out += f.feed(String(text[i..<j]))
            i = j
        }
        out += f.finish()
        return (out, f.calls)
    }

    private func everySize(_ text: String, _ check: (String, [ToolCall]) -> Void) {
        for size in [1, 2, 3, 5, 7, 13, 1000] {
            let (shown, calls) = filtered(text, size: size)
            check(shown, calls)
        }
    }

    func testTheCallFromTheReportIsCut() {
        everySize(#"<tool_call>call:search_web{queries:["resultado Flamengo ontem","Flamengo placar"]}</tool_call>"#) { shown, calls in
            XCTAssertEqual(shown, "")
            XCTAssertEqual(calls.map(\.name), ["search_web"])
        }
    }

    func testGemmasOwnTokensAndStringQuotes() {
        everySize(#"<|tool_call>call:search_web{query:<|"|>weather in London today<|"|>}<tool_call|>"#) { shown, calls in
            XCTAssertEqual(shown, "")
            XCTAssertEqual(calls.map(\.name), ["search_web"])
        }
    }

    func testGemmaWithItsSpecialTokensDroppedAtTheStartOfTheReply() {
        everySize(#"call:search_web{query:"Premier League table"}"#) { shown, calls in
            XCTAssertEqual(shown, "")
            XCTAssertEqual(calls.map(\.name), ["search_web"])
        }
        everySize("  call:search_web{query:Premier League table}") { shown, calls in
            XCTAssertEqual(shown, "")
            XCTAssertEqual(calls.map(\.name), ["search_web"])
        }
    }

    func testHermesAndQwenJSONInsideTheTags() {
        everySize(#"<tool_call>{"name": "search_web", "arguments": {"query": "preço do bitcoin"}}</tool_call>"#) { shown, calls in
            XCTAssertEqual(shown, "")
            XCTAssertEqual(calls.map(\.name), ["search_web"])
        }
    }

    func testMistralsMarkerRunsToTheEnd() {
        everySize(#"[TOOL_CALLS][{"name": "web_search", "arguments": {"q": "eclipse 2026"}}]"#) { shown, calls in
            XCTAssertEqual(shown, "")
            XCTAssertEqual(calls.map(\.name), ["web_search"])
        }
    }

    func testTextAroundTheCallIsKept() {
        everySize(#"Vou procurar. <tool_call>call:search_web{query:"x y"}</tool_call>"#) { shown, calls in
            XCTAssertEqual(shown, "Vou procurar. ")
            XCTAssertEqual(calls.count, 1)
        }
    }

    func testAnUnclosedCallIsStillACall() {
        everySize(#"<|tool_call>call:search_web{query:<|"|>libra hoje"#) { shown, calls in
            XCTAssertEqual(shown, "")
            XCTAssertEqual(calls.map(\.name), ["search_web"])
        }
    }

    func testOrdinaryTextPassesUntouched() {
        for text in ["call me tomorrow", "Calma, já vai.", "c", "ca", "a < b e b > c",
                     "<b>negrito</b> e <tool> sem nada", "Use `<tool_call>` em código? Não aqui.",
                     "Recall: call:it", "1 < 2"] {
            everySize(text) { shown, calls in
                XCTAssertEqual(shown, text)
                XCTAssertTrue(calls.isEmpty, text)
            }
        }
    }

    func testStrippingHistoryLeavesFencedCodeAlone() {
        XCTAssertEqual(ToolCallText.stripped(#"<tool_call>call:search_web{queries:["a"]}</tool_call>"#), "")
        XCTAssertEqual(ToolCallText.stripped("Olá"), "Olá")
        let code = "Formato:\n```\n<tool_call>{\"name\":\"x\"}</tool_call>\n```"
        XCTAssertEqual(ToolCallText.stripped(code), code)
    }

    /// A model explaining the format writes it in code: that is the answer,
    /// not a call, and it streamed into nothing.
    func testACallInsideFencedCodeIsShown() {
        let text = "Formato Hermes:\n```\n<tool_call>{\"name\": \"x\"}</tool_call>\n```\nPronto."
        everySize(text) { shown, calls in
            XCTAssertEqual(shown, text)
            XCTAssertTrue(calls.isEmpty)
        }
        everySize(#"<tool_call>call:search_web{q:"a"}</tool_call>Ex.: ```<tool_call>{}</tool_call>```"#) { shown, calls in
            XCTAssertEqual(shown, "Ex.: ```<tool_call>{}</tool_call>```")
            XCTAssertEqual(calls.count, 1)
        }
    }

    func testACallInInlineCodeIsShown() {
        everySize("Abra com `<tool_call>` e feche com `</tool_call>`.") { shown, calls in
            XCTAssertEqual(shown, "Abra com `<tool_call>` e feche com `</tool_call>`.")
            XCTAssertTrue(calls.isEmpty)
        }
    }
}
