import XCTest
@testable import Odysseus

/// Adding a cloud API used to mean knowing its base URL by heart. The web
/// recognises a key by its prefix (`static/js/slashCommands.js`,
/// PROVIDER_PATTERNS) and offers a provider list (`static/index.html`,
/// adm-epProvider); these pin the app's copy of both.
final class ProviderPresetTests: XCTestCase {

    func testAGeminiKeyIsRecognised() {
        let p = ProviderPreset.detect(key: "AIzaSyA-fake-key-for-tests-000000000")
        XCTAssertEqual(p?.name, "Google Gemini")
        XCTAssertEqual(p?.baseURL, "https://generativelanguage.googleapis.com/v1beta/openai")
    }

    func testEveryPrefixTheWebKnows() {
        XCTAssertEqual(ProviderPreset.detect(key: "sk-ant-api03-x")?.name, "Anthropic")
        XCTAssertEqual(ProviderPreset.detect(key: "sk-or-v1-x")?.name, "OpenRouter")
        XCTAssertEqual(ProviderPreset.detect(key: "sk-proj-x")?.name, "OpenAI")
        XCTAssertEqual(ProviderPreset.detect(key: "gsk_x")?.name, "Groq")
        XCTAssertEqual(ProviderPreset.detect(key: "xai-x")?.name, "xAI Grok")
        XCTAssertEqual(ProviderPreset.detect(key: "nvapi-x")?.name, "NVIDIA")
    }

    /// A pasted key often carries the newline or space it was copied with.
    func testWhitespaceAroundAPastedKeyIsIgnored() {
        XCTAssertEqual(ProviderPreset.detect(key: "  AIzaSyB-another-fake-key-00000\n")?.name, "Google Gemini")
    }

    /// "sk-" alone is every OpenAI-compatible vendor's prefix, so it proves nothing.
    func testAnAmbiguousKeyIsNotGuessed() {
        XCTAssertNil(ProviderPreset.detect(key: "sk-1234"))
        XCTAssertNil(ProviderPreset.detect(key: ""))
    }

    /// The same list the web's provider picker offers, minus the two device
    /// flows that already have their own cards.
    func testTheListMatchesTheWebPicker() {
        XCTAssertEqual(ProviderPreset.all.count, 16)
        XCTAssertTrue(ProviderPreset.all.contains { $0.baseURL == "https://api.deepseek.com/v1" })
        XCTAssertEqual(Set(ProviderPreset.all.map(\.id)).count, ProviderPreset.all.count, "ids must be unique")
    }

    func testMatchingAnURLBackToItsPreset() {
        XCTAssertEqual(ProviderPreset.matching(url: "https://generativelanguage.googleapis.com/v1beta/openai/")?.name, "Google Gemini")
        XCTAssertNil(ProviderPreset.matching(url: "http://192.168.0.10:11434/v1"))
    }

    // MARK: - The form

    @MainActor
    func testPastingAGeminiKeyFillsTheForm() {
        let vm = AddModelsVM(api: APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!)))
        vm.apiKey = "AIzaSyA-fake-key-for-tests-000000000"
        XCTAssertEqual(vm.baseURL, "https://generativelanguage.googleapis.com/v1beta/openai")
        XCTAssertEqual(vm.kind, "api")
        XCTAssertEqual(vm.preset?.name, "Google Gemini")
        XCTAssertTrue(vm.recognised)
        XCTAssertTrue(vm.canAdd)
    }

    /// The owner's Gemini ended up registered as an *image* endpoint — the
    /// "Imagem" chip was on when the key went in — and the chat picker (app and
    /// web alike) skips image endpoints whole, so Gemini and Gemma never showed.
    /// A cloud key names a chat API; the chip follows it.
    @MainActor
    func testAKnownKeyUnderTheImageChipStillMeansAPI() {
        let vm = AddModelsVM(api: APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!)))
        vm.kind = "image"
        vm.apiKey = "AIzaSyA-fake-key-for-tests-000000000"
        XCTAssertEqual(vm.kind, "api")
        XCTAssertEqual(vm.baseURL, "https://generativelanguage.googleapis.com/v1beta/openai")
    }

    @MainActor
    func testAURLTheUserTypedIsNeverOverwritten() {
        let vm = AddModelsVM(api: APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!)))
        vm.kind = "api"
        vm.baseURL = "https://my-gemini-proxy.test/v1"
        vm.apiKey = "AIzaSyA-fake-key-for-tests-000000000"
        XCTAssertEqual(vm.baseURL, "https://my-gemini-proxy.test/v1")
        XCTAssertFalse(vm.recognised)
    }

    @MainActor
    func testAddingSendsTheCleanURLAndTheProvidersName() async {
        StubTransport.reset()
        defer { StubTransport.reset() }
        StubTransport.route("/api/model-endpoints", .json(#"""
        {"id": "g1", "status": "online", "online": true,
         "models": ["gemini-2.5-flash", "gemma-3-27b-it", "gemini-3.8-flash-tts", "gemini-2.5-flash-image"]}
        """#))
        let api = APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!),
                            protocolClasses: [StubTransport.self])
        let vm = AddModelsVM(api: api)
        vm.apiKey = "  AIzaSyA-fake-key-for-tests-000000000\n"
        await vm.add()
        let raw = String(decoding: StubTransport.sentBodies["/api/model-endpoints"] ?? Data(), as: UTF8.self)
        XCTAssertTrue(raw.contains("base_url=https%3A%2F%2Fgenerativelanguage.googleapis.com%2Fv1beta%2Fopenai"), raw)
        XCTAssertTrue(raw.contains("name=Google%20Gemini") || raw.contains("name=Google+Gemini"), raw)
        XCTAssertTrue(raw.contains("api_key=AIzaSyA-fake-key-for-tests-000000000&") || raw.hasSuffix("api_key=AIzaSyA-fake-key-for-tests-000000000"),
                      "the pasted newline must not reach the server: \(raw)")
        XCTAssertTrue(vm.ok)
        XCTAssertTrue(vm.message?.contains("Voz (TTS)") == true, vm.message ?? "nil")
    }

    // MARK: - Base URL clean-up (the web's _normalizeBaseUrl)

    func testAPublicHostWithoutSchemeGetsHTTPS() {
        // Sent bare, the server prefixes http:// and Google's native model
        // listing then fails on the plain-HTTP host — a valid key reads as dead.
        XCTAssertEqual(ProviderPreset.normalize("generativelanguage.googleapis.com/v1beta/openai"),
                       "https://generativelanguage.googleapis.com/v1beta/openai")
    }

    func testALocalHostWithoutSchemeGetsHTTP() {
        XCTAssertEqual(ProviderPreset.normalize("192.168.0.10:11434/v1"), "http://192.168.0.10:11434/v1")
        XCTAssertEqual(ProviderPreset.normalize("localhost:1234/v1/"), "http://localhost:1234/v1")
    }

    func testPastedRouteTailsAreStripped() {
        XCTAssertEqual(ProviderPreset.normalize("https://api.openai.com/v1/chat/completions"), "https://api.openai.com/v1")
        XCTAssertEqual(ProviderPreset.normalize("https://api.openai.com/v1/models/"), "https://api.openai.com/v1")
        XCTAssertEqual(ProviderPreset.normalize("https://x.test/v1/v1"), "https://x.test/v1")
        XCTAssertEqual(ProviderPreset.normalize(" https:/api.groq.com/openai/v1?x=1 "), "https://api.groq.com/openai/v1")
    }
}
