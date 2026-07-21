import XCTest
@testable import Odysseus

/// `GET /api/models` grew per-group fields on newer servers (`models_extra`,
/// `models_display`, `endpoint_name`, `model_type`). All of them are optional
/// in the client so an older server — which sends none — must produce the
/// exact pre-existing picker: every model visible, name derived from the id.
final class ModelsListDecodingTests: XCTestCase {

    private func parse(_ json: String) -> [ChatModel]? {
        APIClient.parseGroupedModels(Data(json.utf8))
    }

    /// Old server: bare `{url, endpoint_id, models:[id]}` groups, nothing else.
    func testOldServerShapeUnchanged() {
        let out = parse(#"""
        {"hosts": [], "items": [
          {"url": "http://10.0.0.5:8080/v1/chat/completions", "endpoint_id": "ep1",
           "models": ["meta/llama-3-8b", "qwen3"]}
        ]}
        """#)
        XCTAssertEqual(out?.count, 2)
        XCTAssertEqual(out?[0].id, "meta/llama-3-8b")
        XCTAssertEqual(out?[0].name, "llama-3-8b")
        XCTAssertEqual(out?[0].isExtra, false)
        XCTAssertNil(out?[0].endpointName)
        XCTAssertEqual(out?[1].name, "qwen3")
    }

    /// New server: curated + extra merge (extras after, flagged), display
    /// names win over id-derivation, endpoint_name carried through.
    func testNewServerCuratedPlusExtraMerged() {
        let out = parse(#"""
        {"hosts": [], "items": [
          {"url": "https://openrouter.ai/api/v1/chat/completions", "endpoint_id": "or",
           "endpoint_name": "OpenRouter", "model_type": "llm",
           "models": ["anthropic/claude-sonnet-5"],
           "models_display": ["Claude Sonnet 5"],
           "models_extra": ["mistralai/mistral-small"],
           "models_extra_display": ["Mistral Small"]}
        ]}
        """#)
        XCTAssertEqual(out?.count, 2)
        XCTAssertEqual(out?[0].name, "Claude Sonnet 5")
        XCTAssertEqual(out?[0].isExtra, false)
        XCTAssertEqual(out?[1].id, "mistralai/mistral-small")
        XCTAssertEqual(out?[1].name, "Mistral Small")
        XCTAssertEqual(out?[1].isExtra, true)
        XCTAssertEqual(out?[0].endpointName, "OpenRouter")
    }

    /// Non-LLM endpoints (diffusion/embedding) must not reach the chat picker —
    /// but a missing model_type (old server) means "llm".
    func testNonLLMEndpointFilteredOnlyWhenTyped() {
        let out = parse(#"""
        {"hosts": [], "items": [
          {"endpoint_id": "sd", "model_type": "diffusion", "models": ["sdxl"]},
          {"endpoint_id": "old", "models": ["gemma"]}
        ]}
        """#)
        XCTAssertEqual(out?.count, 1)
        XCTAssertEqual(out?[0].id, "gemma")
    }

    /// A display array that doesn't line up with the ids (server bug / partial
    /// data) is ignored wholesale rather than mislabeling models.
    func testMisalignedDisplayNamesFallBackToIds() {
        let out = parse(#"""
        {"hosts": [], "items": [
          {"endpoint_id": "e", "models": ["a/x", "b/y"], "models_display": ["Only One"]}
        ]}
        """#)
        XCTAssertEqual(out?.map(\.name), ["x", "y"])
    }

    /// Offline groups come with empty model lists and must contribute nothing.
    func testOfflineGroupYieldsNothing() {
        let out = parse(#"""
        {"hosts": [], "items": [
          {"endpoint_id": "down", "models": [], "models_extra": [], "offline": true}
        ]}
        """#)
        XCTAssertEqual(out?.count, 0)
    }

    /// Not the grouped shape at all → nil, so models() falls back to the bare list.
    func testNonGroupedPayloadReturnsNil() {
        XCTAssertNil(parse(#"[{"id": "m1", "name": "M1"}]"#))
    }
}
