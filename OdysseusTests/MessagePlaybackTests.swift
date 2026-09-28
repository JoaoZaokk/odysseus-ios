import XCTest
@testable import Odysseus

/// The 🔊 on a message used to fail without a word when the "Servidor" voice
/// could not speak — and on the current server that is most configurations:
/// `tts_provider` defaults to "disabled" (503), "browser" means *the client
/// speaks* and `/api/tts/synthesize` answers 500 for it every time, and
/// Kokoro became an optional install (upstream f562bfe), so "local" without it
/// is 503 too. The button spun, stopped, and nothing played. Reading a message
/// aloud now always ends in sound: the configured voice, or the device's own
/// with a line saying why.
@MainActor
final class MessagePlaybackTests: XCTestCase {

    private var savedEngine: Any?

    override func setUp() {
        super.setUp()
        StubTransport.reset()
        savedEngine = UserDefaults.standard.object(forKey: TTSEngine.key)
        UserDefaults.standard.set(TTSEngine.server.rawValue, forKey: TTSEngine.key)
    }

    override func tearDown() {
        UserDefaults.standard.set(savedEngine, forKey: TTSEngine.key)
        StubTransport.reset()
        super.tearDown()
    }

    private func client() -> APIClient {
        APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!),
                  protocolClasses: [StubTransport.self])
    }

    private func waitUntil(_ timeout: TimeInterval = 3, _ cond: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !cond() && Date() < end { try? await Task.sleep(nanoseconds: 50_000_000) }
    }

    // MARK: - Pure decisions

    func testTheServersBrowserProviderMeansTheDeviceSpeaks() {
        XCTAssertEqual(SpeechManager.effectiveEngine(.server, serverProvider: "browser"), .native)
        XCTAssertEqual(SpeechManager.effectiveEngine(.server, serverProvider: "local"), .server)
        XCTAssertEqual(SpeechManager.effectiveEngine(.server, serverProvider: nil), .server)
        XCTAssertEqual(SpeechManager.effectiveEngine(.endpoint, serverProvider: "browser"), .endpoint,
                       "only the server engine reads the server's provider")
    }

    func testOnlyAMessageReadAloudFallsBack() {
        struct Boom: Error {}
        XCTAssertTrue(SpeechManager.fallsBackToNative(engine: .server, duplex: false, error: Boom()))
        XCTAssertTrue(SpeechManager.fallsBackToNative(engine: .endpoint, duplex: false, error: Boom()))
        XCTAssertTrue(SpeechManager.fallsBackToNative(engine: .neural, duplex: false, error: Boom()))
        XCTAssertFalse(SpeechManager.fallsBackToNative(engine: .native, duplex: false, error: Boom()),
                       "nothing left to fall back to")
        XCTAssertFalse(SpeechManager.fallsBackToNative(engine: .server, duplex: true, error: Boom()),
                       "the voice loop owns its own failure path (onSpeechFailed)")
        XCTAssertFalse(SpeechManager.fallsBackToNative(engine: .server, duplex: false, error: CancellationError()),
                       "a stop is not a failure")
    }

    // MARK: - Through the wire

    func testA503FromTheServerStillReadsTheMessageAndSaysWhy() async {
        StubTransport.route("/api/tts/stats", .json(#"{"available": false, "provider": "disabled"}"#))
        StubTransport.route("/api/tts/synthesize",
                            .json(#"{"detail": {"message": "TTS service not available"}}"#, status: 503))
        let sm = SpeechManager()
        sm.api = client()
        sm.toggle("Olá, isto é um teste.", id: "m1")
        await waitUntil { sm.notice?.id == "m1" }
        XCTAssertEqual(sm.notice?.id, "m1", "the failure has to reach the message, not only Settings")
        XCTAssertTrue(sm.notice?.text.contains("TTS service not available") == true, sm.notice?.text ?? "nil")
        XCTAssertTrue(StubTransport.seen.contains("/api/tts/synthesize"))
        sm.stop()
    }

    func testTheBrowserProviderNeverCallsSynthesize() async {
        StubTransport.route("/api/tts/stats", .json(#"{"available": true, "provider": "browser"}"#))
        StubTransport.route("/api/tts/synthesize", .json(#"{"detail": {"message": "Synthesis failed"}}"#, status: 500))
        let sm = SpeechManager()
        sm.api = client()
        sm.toggle("Olá, isto é um teste.", id: "m2")
        await waitUntil { StubTransport.seen.contains("/api/tts/stats") && sm.serverStats != nil }
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(StubTransport.seen.contains("/api/tts/synthesize"),
                       "\"browser\" is the server telling the client to speak; the route 500s for it")
        XCTAssertNil(sm.notice, "nothing failed")
        sm.stop()
    }

    /// Settings' "test the server voice" must not pass by speaking another voice.
    func testTheSettingsVoiceTestDoesNotHideAFailure() async {
        StubTransport.route("/api/tts/stats", .json(#"{"available": false, "provider": "disabled"}"#))
        StubTransport.route("/api/tts/synthesize", .json(#"{"detail": {"message": "TTS service not available"}}"#, status: 503))
        let sm = SpeechManager()
        sm.api = client()
        sm.toggle("Olá! Esta é a voz do servidor.", id: SpeechManager.testID)
        await waitUntil { sm.neuralError != nil }
        XCTAssertNotNil(sm.neuralError, "the test reports the failure")
        XCTAssertNil(sm.notice, "and does not answer in the device's voice")
        XCTAssertFalse(sm.isSpeaking(SpeechManager.testID))
        sm.stop()
    }

    func testStoppingClearsTheNotice() async {
        StubTransport.route("/api/tts/stats", .json(#"{"available": false, "provider": "disabled"}"#))
        StubTransport.route("/api/tts/synthesize", .json(#"{"detail": "no"}"#, status: 503))
        let sm = SpeechManager()
        sm.api = client()
        sm.toggle("Um teste.", id: "m3")
        await waitUntil { sm.notice != nil }
        sm.toggle("Outro.", id: "m4")
        XCTAssertNil(sm.notice, "a new message starts clean")
        sm.stop()
    }
}
