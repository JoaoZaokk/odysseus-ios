import Foundation

extension APIClient {
    func notes() async throws -> [Note] {
        decodeList(Note.self, try await send(request("/api/notes")))
    }

    func createNote(_ payload: NotePayload) async throws {
        let req = try jsonRequest("/api/notes", method: "POST", body: payload)
        _ = try await send(req)
    }

    func updateNote(_ id: String, _ payload: NotePayload) async throws {
        let req = try jsonRequest("/api/notes/\(id)", method: "PUT", body: payload)
        _ = try await send(req)
    }

    /// Partial update (e.g. just toggling `archived`).
    func patchNote(_ id: String, fields: [String: Bool]) async throws {
        struct Flags: Encodable {
            let archived: Bool?; let pinned: Bool?
        }
        let body = Flags(archived: fields["archived"], pinned: fields["pinned"])
        let req = try jsonRequest("/api/notes/\(id)", method: "PUT", body: body)
        _ = try await send(req)
    }

    func deleteNote(_ id: String) async throws {
        _ = try await send(request("/api/notes/\(id)", method: "DELETE"))
    }
}
