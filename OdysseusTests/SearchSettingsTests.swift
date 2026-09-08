import XCTest
@testable import Odysseus

/// What Settings › Busca posts, and what it refuses to post.
///
/// 1.8 posted whatever was typed: `research_max_tokens = 0` went straight to
/// the model provider (the server never clamps it), a failed load meant the
/// next Return posted the app's placeholders over the server's real values,
/// and an emptied key was dropped from the body, so a stored key could not be
/// cleared from the phone.
@MainActor
final class SearchSettingsTests: XCTestCase {

    override func setUp() { super.setUp(); StubTransport.reset() }
    override func tearDown() { StubTransport.reset(); super.tearDown() }

    private func client() -> APIClient {
        APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!),
                  protocolClasses: [StubTransport.self])
    }

    private var posted: [String: Any] {
        guard let d = StubTransport.sentBodies["/api/auth/settings"] else { return [:] }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
    }

    private let served = #"""
    {"search_provider": "brave", "search_result_count": 7, "brave_api_key": "bsk-live",
     "research_max_tokens": 20000, "research_extraction_timeout_seconds": 120,
     "research_extraction_concurrency": 4, "research_run_timeout_seconds": 3600}
    """#

    // MARK: - Clamps

    func testTheWebsRangesApplyAndTheFieldShowsWhatWasSent() async {
        StubTransport.route("/api/auth/settings", .json(served))
        let vm = SearchSettingsVM(api: client())
        await vm.load()
        vm.maxTokens = "0"; vm.extractTimeout = "5"; vm.extractParallel = "99"; vm.runTimeout = "5"
        await vm.save()

        XCTAssertEqual(posted["research_max_tokens"] as? Int, 1024, "0 tokens breaks every research run")
        XCTAssertEqual(posted["research_extraction_timeout_seconds"] as? Int, 15)
        XCTAssertEqual(posted["research_extraction_concurrency"] as? Int, 12)
        XCTAssertEqual(posted["research_run_timeout_seconds"] as? Int, 60)
        XCTAssertEqual(vm.maxTokens, "1024", "the field must show the value that will apply")
        XCTAssertEqual(vm.runTimeout, "60")
    }

    func testZeroRunTimeoutMeansNoCapAndStaysZero() {
        XCTAssertEqual(SearchSettingsVM.clampedRunTimeout("0"), 0)
        XCTAssertEqual(SearchSettingsVM.clampedRunTimeout("-3"), 60)
        XCTAssertEqual(SearchSettingsVM.clampedRunTimeout("999999"), 86400)
        XCTAssertEqual(SearchSettingsVM.clampedTokens("abc"), 16384, "garbage falls back to the default, not to 0")
    }

    // MARK: - A failed load must not become a save

    func testNothingIsPostedWhileTheServersValuesAreUnknown() async {
        StubTransport.route("/api/auth/settings", .json(#"{"detail": "nope"}"#, status: 500))
        let vm = SearchSettingsVM(api: client())
        await vm.load()
        XCTAssertFalse(vm.loaded)
        await vm.save()
        XCTAssertEqual(StubTransport.methods["/api/auth/settings"], "GET",
                       "the only traffic may be the retried load — never a POST of placeholders")
        XCTAssertEqual(vm.status, "Falha ao salvar")
    }

    func testSaveRetriesTheLoadFirstAndThenPosts() async {
        StubTransport.route("/api/auth/settings", .json(served))
        let vm = SearchSettingsVM(api: client())
        // Never loaded: save() loads, adopts the server's values, then posts them.
        await vm.save()
        XCTAssertTrue(vm.loaded)
        XCTAssertEqual(posted["search_provider"] as? String, "brave")
        XCTAssertEqual(posted["research_max_tokens"] as? Int, 20000)
    }

    // MARK: - The key field

    func testAnUneditedKeyIsNeverPosted() async {
        // GET blanks every key for a non-admin. Posting the blank back would
        // erase the admin's real key.
        StubTransport.route("/api/auth/settings", .json(#"{"search_provider": "brave", "brave_api_key": ""}"#))
        let vm = SearchSettingsVM(api: client())
        await vm.load()
        vm.count = "9"
        await vm.save()
        XCTAssertNil(posted["brave_api_key"])
        XCTAssertEqual(posted["search_result_count"] as? Int, 9)
    }

    func testAnEmptiedKeyIsPostedAsEmptySoItCanBeCleared() async {
        StubTransport.route("/api/auth/settings", .json(served))
        let vm = SearchSettingsVM(api: client())
        await vm.load()
        vm.keyBinding.wrappedValue = ""
        await vm.save()
        XCTAssertEqual(posted["brave_api_key"] as? String, "")
    }

    func testAnEditedKeyGoesUnderTheSelectedProvidersName() async {
        StubTransport.route("/api/auth/settings", .json(served))
        let vm = SearchSettingsVM(api: client())
        await vm.load()
        vm.provider = "tavily"
        vm.keyBinding.wrappedValue = "tvly-new"
        await vm.save()
        XCTAssertEqual(posted["tavily_api_key"] as? String, "tvly-new")
        XCTAssertNil(posted["brave_api_key"], "the other provider's slot is not touched")
    }
}
