import XCTest
@testable import Odysseus

/// `CalendarEvent.parse` handles the mix the server emits: naive *local*
/// datetimes (relative-time events keep `datetime.now()` microseconds, e.g.
/// "2026-07-16T11:30:00.123456"), timezone-aware ISO strings, and date-only
/// all-day events.
final class CalendarEventParseTests: XCTestCase {

    /// 2026-07-16 09:30:00 in the device's local timezone.
    private var localNineThirty: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 16
        c.hour = 9; c.minute = 30; c.second = 0
        c.timeZone = .current
        return Calendar.current.date(from: c)!
    }

    /// 2026-07-16 00:00:00 in the device's local timezone.
    private var localMidnight: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 16
        c.timeZone = .current
        return Calendar.current.date(from: c)!
    }

    func testNaiveLocal() {
        XCTAssertEqual(CalendarEvent.parse("2026-07-16T09:30:00"), localNineThirty)
    }

    /// Regression: the strict local formatter rejected the fraction, so the
    /// string fell through to ISODate, got a "Z" appended, and displayed
    /// shifted by the device's UTC offset.
    func testNaiveLocalWithMicroseconds() {
        XCTAssertEqual(CalendarEvent.parse("2026-07-16T09:30:00.123456"), localNineThirty)
    }

    func testNaiveLocalWithMilliseconds() {
        XCTAssertEqual(CalendarEvent.parse("2026-07-16T09:30:00.123"), localNineThirty)
    }

    func testZuluSuffix() {
        XCTAssertEqual(CalendarEvent.parse("2026-07-16T12:30:00Z"),
                       Date(timeIntervalSince1970: 1_784_205_000))
    }

    func testZuluSuffixWithFraction() {
        let d = CalendarEvent.parse("2026-07-16T12:30:00.123456Z")
        XCTAssertNotNil(d)
        XCTAssertEqual(d!.timeIntervalSince1970, 1_784_205_000.123, accuracy: 0.001)
    }

    func testPositiveOffset() {
        XCTAssertEqual(CalendarEvent.parse("2026-07-16T14:30:00+02:00"),
                       Date(timeIntervalSince1970: 1_784_205_000))
    }

    /// Regression: negative-offset strings slipped past the naive check
    /// (no "Z"/"+") and ICU either parsed them ignoring the offset (iOS 26)
    /// or rejected them into the date-only fallback (macOS host) — behavior
    /// differed by platform. Now the "-" after the date part routes them to
    /// ISODate, which honors the offset.
    func testNegativeOffset() {
        XCTAssertEqual(CalendarEvent.parse("2026-07-16T09:30:00-03:00"),
                       Date(timeIntervalSince1970: 1_784_205_000))
    }

    func testNegativeOffsetWithFraction() {
        let d = CalendarEvent.parse("2026-07-16T09:30:00.123456-03:00")
        XCTAssertNotNil(d)
        XCTAssertEqual(d!.timeIntervalSince1970, 1_784_205_000.123, accuracy: 0.001)
    }

    func testDateOnly() {
        XCTAssertEqual(CalendarEvent.parse("2026-07-16"), localMidnight)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(CalendarEvent.parse("not-a-date"))
        XCTAssertNil(CalendarEvent.parse(""))
    }
}
