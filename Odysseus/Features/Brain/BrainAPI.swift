import Foundation

extension APIClient {
    func memories() async throws -> [Memory] {
        decodeList(Memory.self, try await send(request("/api/memory")))
    }

    func addMemory(text: String, category: String?) async throws {
        struct Body: Encodable { let text: String; let category: String? }
        let req = try jsonRequest("/api/memory/add", method: "POST",
                                  body: Body(text: text, category: category))
        _ = try await send(req)
    }

    func deleteMemory(_ id: String) async throws {
        _ = try await send(request("/api/memory/\(encPath(id))", method: "DELETE"))
    }

    func pinMemory(_ id: String) async throws {
        _ = try await send(request("/api/memory/\(encPath(id))/pin", method: "POST"))
    }

    /// AI "tidy" pass that de-dupes and cleans the memory list. Returns the
    /// server's summary so the UI can report what happened.
    func auditMemories() async throws -> AuditResult {
        let data = try await send(request("/api/memory/audit", method: "POST"))
        return (try? JSONDecoder().decode(AuditResult.self, from: data)) ?? AuditResult()
    }
}

struct AuditResult: Decodable {
    var removed: Int = 0
    var before: Int = 0
    var after: Int = 0
}
