import XCTest
@testable import Odysseus

/// Three Settings screens that used to report a state the server did not
/// have: a reminder test that always "fired", an endpoint that was always
/// "Adicionado", and a fallback editor bound to a key the server had retired.
@MainActor
final class SettingsWiresTests: XCTestCase {

    override func setUp() { super.setUp(); StubTransport.reset() }
    override func tearDown() { StubTransport.reset(); super.tearDown() }

    private func client() -> APIClient {
        APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!),
                  protocolClasses: [StubTransport.self])
    }

    private func json(_ path: String) -> [String: Any] {
        guard let d = StubTransport.sentBodies[path] else { return [:] }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
    }

    private func form(_ path: String) -> [String: String] {
        let raw = String(decoding: StubTransport.sentBodies[path] ?? Data(), as: UTF8.self)
        var out: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            out[kv[0].removingPercentEncoding ?? kv[0]] = kv[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? kv[1]
        }
        return out
    }

    // MARK: - Reminders

    func testTheTestReminderCarriesAnAdminTestIdAndTheForm() async throws {
        StubTransport.route("/api/notes/fire-reminder", .json(#"{"channel": "ntfy", "ntfy_sent": true, "ntfy_error": null}"#))
        try await client().fireTestReminder(channel: "ntfy", webhookId: "", template: "", synthesis: true, persona: "spark")
        let b = json("/api/notes/fire-reminder")
        XCTAssertTrue((b["note_id"] as? String ?? "").hasPrefix("test-"), "the route only treats test- ids as a dry run")
        XCTAssertEqual(b["channel"] as? String, "ntfy")
        XCTAssertEqual(b["llm_synthesis"] as? Bool, true)
        XCTAssertEqual(b["llm_persona"] as? String, "spark")
    }

    func testADeliveryErrorInA200BodyIsAFailure() async {
        // The server answers 200 and puts the failure in `<channel>_error`.
        StubTransport.route("/api/notes/fire-reminder",
                            .json(#"{"channel": "webhook", "webhook_sent": false, "webhook_error": "No payload template configured"}"#))
        let vm = RemindersVM(api: client())
        vm.channel = "webhook"
        await vm.test()
        XCTAssertEqual(vm.note, "Falha no teste: No payload template configured")
    }

    func testTheWebhookTemplateIsPersisted() async {
        StubTransport.route("/api/auth/settings", .json("{}"))
        let vm = RemindersVM(api: client())
        vm.channel = "webhook"; vm.webhookTemplate = #"{"content": "{{title}}"}"#
        await vm.save()
        XCTAssertEqual(json("/api/auth/settings")["reminder_webhook_payload_template"] as? String, #"{"content": "{{title}}"}"#)
    }

    // MARK: - Endpoints

    func testADeadHostIsNotReportedAsAdded() async {
        StubTransport.route("/api/model-endpoints",
                            .json(#"{"id": "e1", "status": "offline", "online": false, "models": [], "ping_error": "connection refused"}"#))
        let vm = AddModelsVM(api: client())
        vm.baseURL = "http://10.0.0.9:11434/v1"
        await vm.add()
        XCTAssertFalse(vm.ok)
        XCTAssertEqual(vm.message, "Falha: connection refused")
        XCTAssertEqual(vm.baseURL, "http://10.0.0.9:11434/v1", "the form stays so the user can fix the URL")
    }

    func testALiveHostReportsItsModelCount() async {
        StubTransport.route("/api/model-endpoints",
                            .json(#"{"id": "e1", "status": "online", "online": true, "models": ["a", "b", "c"]}"#))
        let vm = AddModelsVM(api: client())
        vm.baseURL = "http://localhost:11434/v1"
        await vm.add()
        XCTAssertTrue(vm.ok)
        XCTAssertEqual(vm.message, "Conectado: 3 modelos.")
        XCTAssertEqual(vm.baseURL, "")
    }

    func testAnImageEndpointSaysSoAndNothingElseIsHardcoded() async throws {
        StubTransport.route("/api/model-endpoints", .json(#"{"id": "e1", "status": "online", "models": []}"#))
        _ = try await client().createEndpoint(name: "sd", baseURL: "http://sd:7860", apiKey: nil, kind: "image")
        let f = form("/api/model-endpoints")
        XCTAssertEqual(f["model_type"], "image", "omitting it would let the server demote an existing image row to llm")
        XCTAssertNil(f["category"], "the route has no such field")
        _ = try await client().createEndpoint(name: "o", baseURL: "http://o:11434", apiKey: nil, kind: "local")
        XCTAssertEqual(form("/api/model-endpoints")["model_type"], "llm")
    }

    func testTheRowKnowsItsTotalNotJustTheVisibleModels() throws {
        let raw = #"{"id": "e1", "name": "x", "is_enabled": true, "models": [], "model_count": 57, "hidden_count": 57, "model_type": "llm"}"#
        let ep = try JSONDecoder().decode(ModelEndpoint.self, from: Data(raw.utf8))
        XCTAssertEqual(ep.models.count, 0)
        XCTAssertEqual(ep.total, 57, "all hidden is not 'no models in cache'")
        let old = try JSONDecoder().decode(ModelEndpoint.self, from: Data(#"{"id": "e2", "models": ["m"]}"#.utf8))
        XCTAssertEqual(old.total, 1, "an older server without model_count falls back to the visible list")
    }

    // MARK: - Fallback chains

    func testModelFallbacksSaveUnderTheLiveKeysNeverTheRetiredOne() async {
        StubTransport.route("/api/auth/settings",
                            .json(#"{"utility_model_fallbacks": [{"endpoint_id": "e1", "model": "m1"}], "vision_model_fallbacks": []}"#))
        let vm = AIDefaultsVM(api: client())
        StubTransport.route("/api/model-endpoints", .json("[]"))
        await vm.load()
        XCTAssertEqual(vm.chains[.utility]?.map(\.model), ["m1"])
        vm.chains[.vision] = [Fallback(endpointId: "e2", model: "llava"), Fallback(endpointId: "", model: "")]
        await vm.saveFallbacks(.vision)
        let body = json("/api/auth/settings")
        XCTAssertNil(body["default_model_fallbacks"], "retired on the server; 1.8 saved into it and it was thrown away")
        XCTAssertEqual((body["vision_model_fallbacks"] as? [[String: String]])?.count, 1, "the half-filled row is skipped")
        XCTAssertEqual((body["vision_model_fallbacks"] as? [[String: String]])?.first?["model"], "llava")
    }

    func testTheVisionBlocklistMatchesTheWebs() {
        XCTAssertTrue(AIDefaultsVM.isVisionModel("llava:13b"))
        XCTAssertTrue(AIDefaultsVM.isVisionModel("gpt-4o"))
        for bad in ["whisper-1", "tts-1", "text-embedding-3", "dall-e-3", "gpt-4o-realtime"] {
            XCTAssertFalse(AIDefaultsVM.isVisionModel(bad), bad)
        }
        // The web's list says "embedding", not "embed": nomic-embed-text slips
        // through there too. Mirroring the web is the contract, not improving it.
        XCTAssertTrue(AIDefaultsVM.isVisionModel("nomic-embed-text"))
    }

    func testTheSearchChainNeverOffersThePrimaryOrDisabledAndSavesItself() async {
        StubTransport.route("/api/auth/settings", .json(#"{"search_provider": "brave", "search_fallback_chain": ["duckduckgo"]}"#))
        let vm = SearchSettingsVM(api: client())
        await vm.load()
        XCTAssertEqual(vm.fallbackChain, ["duckduckgo"])
        XCTAssertFalse(vm.availableFallbacks.contains("brave"))
        XCTAssertFalse(vm.availableFallbacks.contains("disabled"))
        XCTAssertFalse(vm.availableFallbacks.contains("duckduckgo"), "already in the chain")
        vm.removeFallback(at: 0)
        await vm.saveChain()
        XCTAssertEqual(json("/api/auth/settings")["search_fallback_chain"] as? [String], [],
                       "an empty chain is a real setting: it turns the implicit DuckDuckGo spillover off")
    }
}
