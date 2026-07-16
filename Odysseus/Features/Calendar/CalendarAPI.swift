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

    func deleteEvent(_ uid: String) async throws {
        _ = try await send(request("/api/calendar/events/\(encPath(uid))", method: "DELETE"))
    }

    /// Natural-language event creation: "almoço amanhã 13h". The endpoint asks
    /// the LLM to extract a structured event, so it can return `{ok:false}` if
    /// the model output can't be parsed — surface that as an error.
    func quickParseEvent(_ text: String) async throws {
        struct Body: Encodable { let text: String; let tz: String; let tz_offset: Int }
        let tz = TimeZone.current
        let body = Body(text: text, tz: tz.identifier, tz_offset: tz.secondsFromGMT() / 60)
        let req = try jsonRequest("/api/calendar/quick-parse", method: "POST", body: body)
        let data = try await send(req)
        struct R: Decodable { var ok: Bool?; var error: String? }
        let r = try? JSONDecoder().decode(R.self, from: data)
        if r?.ok == false {
            throw APIError.http(422, r?.error ?? "Não consegui interpretar esse texto. Tente o botão +.")
        }
    }
}
