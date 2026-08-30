import XCTest
@testable import Odysseus

/// The first tests in this bundle that reach past a decoder.
///
/// Before `APIClient(config:protocolClasses:)` existed, all 152 tests were pure
/// decoding and parsing: of the 36 `ObservableObject`s in the app, the bundle
/// constructed zero, and none of the 21 `func load() async` was reachable
/// without a live server. Everything below runs against `StubTransport`.
@MainActor
final class RequestStackTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubTransport.reset()
    }

    override func tearDown() {
        StubTransport.reset()
        super.tearDown()
    }

    private func makeClient() -> APIClient {
        APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!),
                  protocolClasses: [StubTransport.self])
    }

    // MARK: - The seam itself

    func testTheStubIsWhatAnswers() async throws {
        StubTransport.route("/api/memory", .json("[]"))
        _ = try await makeClient().memories()
        XCTAssertTrue(StubTransport.requested("/api/memory"),
                      "the request never reached the stub — check protocolClasses")
    }

    func testAClientWithNoTransportDoesNotReachTheStub() async {
        // The production default must stay the production default. Without the
        // parameter the request leaves for a host that does not resolve, so the
        // stub records nothing.
        StubTransport.route("/api/memory", .json("[]"))
        let live = APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!))
        _ = try? await live.memories()
        XCTAssertFalse(StubTransport.requested("/api/memory"))
    }

    // MARK: - A view model's load path

    func testBrainViewModelPublishesWhatTheServerSaid() async {
        StubTransport.route("/api/memory", .json("""
        [{"id": "1", "text": "gosta de café", "category": "fact", "pinned": false},
         {"id": 2, "content": "mora em SP", "category": "place", "important": true}]
        """))
        let vm = BrainViewModel(api: makeClient())

        await vm.load()

        XCTAssertEqual(vm.memories.count, 2)
        XCTAssertNil(vm.error)
        XCTAssertFalse(vm.loading, "loading must fall back on the way out")
        // The lenient decoder is exercised through the real load path here, not
        // against a hand-fed Data: id-as-Int and the `content`/`important` aliases.
        XCTAssertEqual(vm.memories[1].id, "2")
        XCTAssertEqual(vm.memories[1].text, "mora em SP")
        XCTAssertTrue(vm.memories[1].pinned)
    }

    func testBrainViewModelSurfacesTheServersSentenceOnFailure() async {
        StubTransport.route("/api/memory", .json(#"{"detail": "banco de memórias indisponível"}"#,
                                                 status: 503))
        let vm = BrainViewModel(api: makeClient())

        await vm.load()

        XCTAssertEqual(vm.error, "banco de memórias indisponível")
        XCTAssertTrue(vm.memories.isEmpty)
        XCTAssertFalse(vm.loading)
    }

    func testASecondLoadClearsTheErrorFromTheFirst() async {
        StubTransport.route("/api/memory", .json(#"{"detail": "offline"}"#, status: 500))
        let vm = BrainViewModel(api: makeClient())
        await vm.load()
        XCTAssertEqual(vm.error, "offline")

        StubTransport.route("/api/memory", .json(#"[{"id": "1", "text": "ok", "category": "fact"}]"#))
        await vm.load()

        XCTAssertNil(vm.error, "a successful load must retract the previous error")
        XCTAssertEqual(vm.memories.count, 1)
    }

    // MARK: - The 401 hop

    func testA401CallsBackAndThrowsNotAuthenticated() async {
        StubTransport.route("/api/memory", .json(#"{"detail": "no session"}"#, status: 401))
        let api = makeClient()
        var loggedOut = false
        api.onUnauthenticated = { loggedOut = true }

        do {
            _ = try await api.memories()
            XCTFail("401 must throw")
        } catch APIError.notAuthenticated {
            XCTAssertTrue(loggedOut, "AppState is the only owner of session state — it must be told")
        } catch {
            XCTFail("expected .notAuthenticated, got \(error)")
        }
    }

    func testA403IsNotA401() async {
        // Folding 403 into the 401 branch would log a non-admin out of the app.
        StubTransport.route("/api/memory", .json(#"{"detail": "admin only"}"#, status: 403))
        let api = makeClient()
        var loggedOut = false
        api.onUnauthenticated = { loggedOut = true }

        do {
            _ = try await api.memories()
            XCTFail("403 must throw")
        } catch APIError.http(let code, let detail) {
            XCTAssertEqual(code, 403)
            XCTAssertEqual(detail, "admin only")
            XCTAssertFalse(loggedOut, "403 is 'you may not', not 'you are not'")
        } catch {
            XCTFail("expected .http(403, _), got \(error)")
        }
    }

    // MARK: - The FastAPI 422 reader

    func testFastAPIValidationArrayIsFlattenedIntoOneSentence() async {
        StubTransport.route("/api/memory", .json("""
        {"detail": [{"loc": ["body", "text"], "msg": "field required"},
                    {"loc": ["body", "category"], "msg": "não pode ser vazio"}]}
        """, status: 422))

        do {
            _ = try await makeClient().memories()
            XCTFail("422 must throw")
        } catch APIError.http(let code, let detail) {
            XCTAssertEqual(code, 422)
            XCTAssertEqual(detail, "text: field required · category: não pode ser vazio")
        } catch {
            XCTFail("expected .http(422, _), got \(error)")
        }
    }

    func testAStringDetailIsUsedAsIs() async {
        StubTransport.route("/api/memory", .json(#"{"detail": "servidor ocupado"}"#, status: 500))
        do {
            _ = try await makeClient().memories()
            XCTFail("500 must throw")
        } catch APIError.http(_, let detail) {
            XCTAssertEqual(detail, "servidor ocupado")
        } catch {
            XCTFail("expected .http, got \(error)")
        }
    }

    func testANonJSONBodyIsCappedRatherThanRenderedWhole() async {
        // A hostile server returning megabytes would otherwise land in a Text view.
        StubTransport.route("/api/memory",
                            .init(500, Data(String(repeating: "x", count: 5_000).utf8)))
        do {
            _ = try await makeClient().memories()
            XCTFail("500 must throw")
        } catch APIError.http(_, let detail) {
            XCTAssertEqual(detail?.count, 500)
        } catch {
            XCTFail("expected .http, got \(error)")
        }
    }

    // MARK: - decodeList's two wire shapes

    func testASingleKeyWrapperDecodesLikeABareArray() async throws {
        StubTransport.route("/api/memory",
                            .json(#"{"memories": [{"id": "7", "text": "oi", "category": "fact"}]}"#))
        let list = try await makeClient().memories()
        XCTAssertEqual(list.map(\.id), ["7"])
    }

    func testAnUnrecognisableListDegradesToEmptyRatherThanThrowing() async throws {
        // Deliberate: drift degrades rows, it never fails the screen.
        StubTransport.route("/api/memory", .json(#"{"memories": "nope"}"#))
        let list = try await makeClient().memories()
        XCTAssertTrue(list.isEmpty)
    }

    // MARK: - What the app writes

    func testAddMemoryPostsTheTextAndCategory() async throws {
        StubTransport.route("/api/memory/add", .json("{}"))
        try await makeClient().addMemory(text: "lembrar disso", category: "fact")

        let body = try XCTUnwrap(StubTransport.sentBodies["/api/memory/add"])
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(obj["text"] as? String, "lembrar disso")
        XCTAssertEqual(obj["category"] as? String, "fact")
    }
}
