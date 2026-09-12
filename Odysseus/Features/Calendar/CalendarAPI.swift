import Foundation

extension APIClient {
    func calendars() async throws -> [CalendarInfo] {
        decodeList(CalendarInfo.self, try await send(request("/api/calendar/calendars")))
    }

    func events(start: Date, end: Date) async throws -> [CalendarEvent] {
        // en_US_POSIX forces Gregorian + ASCII digits — the device calendar must
        // never leak into the wire format (Thai devices would query year 2569).
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        let path = "/api/calendar/events?start=\(f.string(from: start))&end=\(f.string(from: end))"
        return decodeList(CalendarEvent.self, try await send(request(path)))
    }

    @discardableResult
    func createEvent(_ payload: EventPayload) async throws -> String {
        let req = try jsonRequest("/api/calendar/events", method: "POST", body: payload)
        struct R: Decodable { var uid: String? }
        let r = try decode(R.self, try await send(req))
        return r.uid ?? ""
    }

    /// `scope` defaults to `series` on the server: deleting an expanded
    /// occurrence by its compound uid without `scope=occurrence` deletes the
    /// whole recurring series (routes/calendar_routes.py `delete_event`).
    func deleteEvent(_ uid: String, occurrenceOnly: Bool = false) async throws {
        let path = "/api/calendar/events/\(encPath(uid))" + (occurrenceOnly ? "?scope=occurrence" : "")
        _ = try await send(request(path, method: "DELETE"))
    }

    /// Natural-language extraction: "almoço amanhã 13h". The endpoint only
    /// PARSES — `{ok, event: {…}, confidence}` — and stores nothing; the web
    /// client posts the result to `/api/calendar/events` itself. 1.9 threw the
    /// event away and reloaded, so quick-add never created anything.
    func quickParseEvent(_ text: String) async throws -> ParsedEvent {
        struct Body: Encodable { let text: String; let tz: String; let tz_offset: Int }
        let tz = TimeZone.current
        let body = Body(text: text, tz: tz.identifier, tz_offset: tz.secondsFromGMT() / 60)
        let req = try jsonRequest("/api/calendar/quick-parse", method: "POST", body: body)
        let data = try await send(req)
        struct R: Decodable { var ok: Bool?; var error: String?; var event: ParsedEvent? }
        let r = try? JSONDecoder().decode(R.self, from: data)
        guard r?.ok != false, let ev = r?.event, !ev.dtstart.isEmpty else {
            throw APIError.http(422, r?.error ?? "Não consegui interpretar esse texto. Tente o botão +.")
        }
        return ev
    }
}
