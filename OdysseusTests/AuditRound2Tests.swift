import XCTest
@testable import Odysseus

/// Covers the round-2 audit fixes whose logic is pure enough to assert directly.
/// Each of these shipped wrong, and each would have been caught by three lines.
final class AuditRound2Tests: XCTestCase {

    // MARK: - #15 — query encoding for a value, not for a whole query string

    func testEncQueryEscapesTheSeparatorsThatSplitAQuery() {
        let api = APIClient(config: ServerConfig(baseURL: URL(string: "https://example.invalid")!))
        XCTAssertEqual(api.encQuery("notas & ideias.md"), "notas%20%26%20ideias.md")
        XCTAssertEqual(api.encQuery("a=b"), "a%3Db")
        XCTAssertEqual(api.encQuery("q?x"), "q%3Fx")
        XCTAssertEqual(api.encQuery("tag#1"), "tag%231")
    }

    /// The bug: `.urlQueryAllowed` leaves `&` alone, so the server saw a truncated
    /// `filepath` and deleted nothing while still answering 200.
    func testUrlQueryAllowedWouldHaveLetTheSeparatorThrough() {
        let raw = "notas & ideias.md".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        XCTAssertEqual(raw, "notas%20&%20ideias.md", "guards the premise of #15")
    }

    // MARK: - #17 — the error message, not the JSON around it

    func testExtractErrorReturnsTheCapturedMessage() {
        let body = #"{"error":true,"message":"rate limit exceeded","code":429}"#
        XCTAssertEqual(ChatStreamClient.extractError(body), "rate limit exceeded")
    }

    func testExtractErrorUnescapesQuotesInsideTheMessage() {
        let body = #"{"message":"model \"gpt-oss\" is not available"}"#
        XCTAssertEqual(ChatStreamClient.extractError(body), #"model "gpt-oss" is not available"#)
    }

    func testExtractErrorFallsBackToAShortBodyAndDropsALongOne() {
        XCTAssertEqual(ChatStreamClient.extractError("upstream unavailable"), "upstream unavailable")
        XCTAssertNil(ChatStreamClient.extractError(String(repeating: "x", count: 500)))
    }

    // MARK: - #19 — an absent setting is not the number zero

    func testIntTextIsEmptyWhenTheServerHasNoSuchSetting() {
        let bag = SettingsBag(dict: [:])
        XCTAssertEqual(bag.intText("agent_max_rounds"), "",
                       "empty lets the field show its placeholder; \"0\" would be saved back as real config")
        XCTAssertEqual(bag.int("agent_max_rounds"), 0, "int() still answers 0 — that is why intText exists")
    }

    func testIntTextReadsBothWireShapes() {
        XCTAssertEqual(SettingsBag(dict: ["agent_max_rounds": 8]).intText("agent_max_rounds"), "8")
        XCTAssertEqual(SettingsBag(dict: ["agent_max_rounds": "12"]).intText("agent_max_rounds"), "12")
        XCTAssertEqual(SettingsBag(dict: ["agent_max_rounds": "oito"]).intText("agent_max_rounds"), "")
    }

    // MARK: - #21 — cancellation is URLError.cancelled, never CancellationError

    func testIsCancellationRecognisesWhatURLSessionActuallyThrows() {
        XCTAssertTrue(URLError(.cancelled).isCancellation)
        XCTAssertTrue(CancellationError().isCancellation)
        XCTAssertFalse(URLError(.timedOut).isCancellation)
        XCTAssertFalse(APIError.notAuthenticated.isCancellation)
    }

    // The premise of #21 needs no test: `URLError(.cancelled) is CancellationError`
    // does not even compile without a warning, because the compiler can prove the
    // cast always fails. That is exactly what `catch is CancellationError` was doing
    // at 21 sites, where the same impossibility is invisible.
}

/// Covers the round-2 *triage* fixes whose logic is pure enough to assert.
final class AuditRound2TriageTests: XCTestCase {

    // MARK: - #58 — a translucent theme is not its opaque original

    func testTranslucentThemeDoesNotEqualItsOpaqueOriginal() {
        let opaque = Theme.all[0]
        let frosted = opaque.translucent(true)
        XCTAssertEqual(frosted.id, opaque.id, "translucency keeps the identity — that is the trap")
        XCTAssertNotEqual(frosted, opaque,
                          "identity-only equality made SwiftUI treat a theme change as no change")
    }

    func testTranslucentFalseIsANoOp() {
        let opaque = Theme.all[0]
        XCTAssertEqual(opaque.translucent(false), opaque)
    }

    // MARK: - #15 — a numeric id decodes, instead of becoming an invented UUID

    func testEndpointDecodesANumericID() throws {
        let json = #"{"id": 7, "name": "local"}"#.data(using: .utf8)!
        let ep = try JSONDecoder().decode(ModelEndpoint.self, from: json)
        XCTAssertEqual(ep.id, "7", "a client-invented UUID makes every button on the row address nothing")
    }

    func testEndpointStillDecodesAStringID() throws {
        let json = #"{"id": "abc", "name": "local"}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(ModelEndpoint.self, from: json).id, "abc")
    }

    // MARK: - #64 — the schedule line resolves through the catalogues

    func testScheduleTextGoesThroughTheLocalizationTable() throws {
        let json = #"{"id": "1", "name": "t", "schedule": "hourly"}"#.data(using: .utf8)!
        let task = try JSONDecoder().decode(ScheduledTask.self, from: json)
        // Under the test bundle's language this resolves to the key itself; the
        // point is that it is a *key*, not interpolated prose no catalogue can match.
        XCTAssertEqual(task.scheduleText, L("De hora em hora"))
    }
}
