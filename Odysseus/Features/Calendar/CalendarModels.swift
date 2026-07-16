import Foundation

/// A calendar from GET /api/calendar/calendars. The id field is `href`.
struct CalendarInfo: Decodable, Identifiable, Hashable, Sendable {
    var href: String
    var name: String
    var color: String?
    var source: String?

    var id: String { href }

    enum CodingKeys: String, CodingKey { case href, name, color, source }
}

/// An event from GET /api/calendar/events?start=&end=.
/// Times are ISO-8601 strings ("2026-06-25T14:00:00"); all-day events use the
/// date portion only.
struct CalendarEvent: Decodable, Identifiable, Hashable, Sendable {
    var uid: String
    var summary: String
    var dtstart: String
    var dtend: String?
    var allDay: Bool
    var location: String
    var description: String
    var calendarHref: String?
    var color: String?

    var id: String { uid }

    enum CodingKeys: String, CodingKey {
        case uid, summary, dtstart, dtend
        case allDay = "all_day"
        case location, description
        case calendarHref = "calendar_href"
        case color
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = (try? c.decode(String.self, forKey: .uid)) ?? UUID().uuidString
        summary = (try? c.decode(String.self, forKey: .summary)) ?? "(sem título)"
        dtstart = (try? c.decode(String.self, forKey: .dtstart)) ?? ""
        dtend = try? c.decodeIfPresent(String.self, forKey: .dtend)
        allDay = (try? c.decode(Bool.self, forKey: .allDay)) ?? false
        location = (try? c.decode(String.self, forKey: .location)) ?? ""
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        calendarHref = try? c.decodeIfPresent(String.self, forKey: .calendarHref)
        color = try? c.decodeIfPresent(String.self, forKey: .color)
    }

    var startDate: Date? { CalendarEvent.parse(dtstart) }
    var endDate: Date? { dtend.flatMap(CalendarEvent.parse) }

    /// Day bucket (start of day) used to group the agenda list.
    var dayKey: Date? {
        guard let d = startDate else { return nil }
        return Calendar.current.startOfDay(for: d)
    }

    static func parse(_ s: String) -> Date? {
        // Server stores naive *local* datetimes ("2026-06-20T09:30:00", no tz),
        // sometimes with fractional seconds ("…T09:30:00.123456" — relative-time
        // events keep datetime.now() microseconds). Parse those as local time
        // first so they don't get shifted by the UTC assumption in ISODate.
        // A "-" after the date part is a UTC offset ("…T09:30:00-03:00"),
        // not a naive datetime (some ICU versions parse it ignoring the
        // offset, which would shift the event).
        if !s.contains("Z") && !s.contains("+") && !s.dropFirst(10).contains("-") {
            var naive = s
            if let dot = naive.firstIndex(of: "."),
               naive.index(after: dot) < naive.endIndex,
               naive[naive.index(after: dot)...].allSatisfy({ $0.isASCII && $0.isNumber }) {
                naive = String(naive[..<dot])
            }
            let local = DateFormatter()
            local.locale = Locale(identifier: "en_US_POSIX")
            local.timeZone = .current
            local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let d = local.date(from: naive) { return d }
        }
        // Timezone-aware ISO ("...Z" / "+hh:mm" / "-hh:mm")
        if let t = ISODate.parse(s) { return Date(timeIntervalSince1970: t) }
        // All-day "2026-06-25". en_US_POSIX like the parser above — with the
        // device calendar, "2026-06-25" parses as a BUDDHIST year on Thai
        // devices and the event lands in Gregorian 1483.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.date(from: String(s.prefix(10)))
    }
}

/// Body for creating an event (POST /api/calendar/events).
struct EventPayload: Encodable {
    var summary: String
    var dtstart: String
    var dtend: String
    var all_day: Bool
    var calendar_href: String
    var location: String?
    var description: String?
}
