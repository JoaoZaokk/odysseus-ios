import XCTest
@testable import Odysseus

/// The owner's Gemini sat on the server as an *image* endpoint (43 models, 33
/// of them chat). `/api/models` hands the picker its `model_type`, and every
/// picker — this app's and the web's — drops non-"llm" groups whole, so none
/// of those chat models could be chosen. The card now says so and offers the
/// one PATCH that fixes it.
@MainActor
final class EndpointTypeTests: XCTestCase {

    override func setUp() { super.setUp(); StubTransport.reset() }
    override func tearDown() { StubTransport.reset(); super.tearDown() }

    private func client() -> APIClient {
        APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!),
                  protocolClasses: [StubTransport.self])
    }

    private func endpoint(_ json: String) throws -> ModelEndpoint {
        try JSONDecoder().decode(ModelEndpoint.self, from: Data(json.utf8))
    }

    func testAnImageEndpointFullOfChatModelsSaysItHidesThem() throws {
        let gemini = try endpoint(#"{"id": "g", "name": "Gemini", "model_type": "image", "models": ["gemini-3.1-pro-preview", "gemini-3-pro-image"]}"#)
        XCTAssertTrue(gemini.hidesChatModels)
        let comfy = try endpoint(#"{"id": "c", "name": "ComfyUI", "model_type": "image", "models": ["flux-dev", "sdxl"]}"#)
        XCTAssertFalse(comfy.hidesChatModels, "an image server with only image models is where it belongs")
        let chat = try endpoint(#"{"id": "o", "name": "Ollama", "model_type": "llm", "models": ["qwen3:8b"]}"#)
        XCTAssertFalse(chat.hidesChatModels)
    }

    /// The route toggles `is_enabled` when the body is empty — so the body must
    /// carry `model_type` and nothing else, never be empty.
    func testSwitchingTheTypeSendsOnlyModelType() async throws {
        StubTransport.route("/api/model-endpoints/g", .json(#"{"id": "g", "is_enabled": true, "model_type": "llm"}"#))
        try await client().setEndpointType("g", modelType: "llm")
        let body = try XCTUnwrap(StubTransport.sentBodies["/api/model-endpoints/g"])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json as NSDictionary, ["model_type": "llm"] as NSDictionary)
    }

    func testUseForChatPatchesThenReloads() async throws {
        StubTransport.route("/api/model-endpoints/g", .json(#"{"id": "g", "model_type": "llm"}"#))
        StubTransport.route("/api/model-endpoints", .json(#"[{"id": "g", "name": "Gemini", "model_type": "llm", "models": ["gemini-3.1-pro-preview"]}]"#))
        let vm = AddedModelsVM(api: client())
        let ep = try endpoint(#"{"id": "g", "name": "Gemini", "model_type": "image", "models": ["gemini-3.1-pro-preview"]}"#)
        await vm.useForChat(ep)
        XCTAssertNil(vm.error)
        XCTAssertEqual(vm.endpoints.first?.isImage, false)
        XCTAssertEqual(StubTransport.seen.filter { $0 == "/api/model-endpoints/g" }.count, 1)
    }
}
