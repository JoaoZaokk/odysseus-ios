import Foundation

// MARK: - Wire models (reverse-engineered from the web's research/* endpoints)

/// Response of `POST /api/research/start`.
struct ResearchStart: Decodable {
    let session_id: String
    var status: String?
    var query: String?
}

/// A `data:` frame from `GET /api/research/stream/{id}` (SSE). All optional —
/// progress frames carry `{phase,total_sources,total_findings,status}`, the
/// closing frame is `{status:"done",final:true}`.
struct ResearchEvent: Decodable {
    var phase: String?
    var status: String?
    var total_sources: Int?
    var total_findings: Int?
    var rounds: Int?
    var source_count: Int?
    var final: Bool?
    var detail: String?
    var message: String?
}

/// An entry from `GET /api/research/active` and `…/library`.
struct ResearchJob: Decodable, Identifiable {
    var session_id: String?
    var id_: String?
    var query: String
    var category: String?
    var source_count: Int?
    var status: String?
    var phase: String?
    var rounds: Int?
    var duration: String?
    var started_at: Double?
    var completed_at: Double?
    var archived: Bool?

    var id: String { session_id ?? id_ ?? query }

    enum CodingKeys: String, CodingKey {
        case session_id, id, query, category, source_count, status, phase
        case rounds, duration, started_at, completed_at, archived
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        session_id = try? c.decode(String.self, forKey: .session_id)
        id_ = try? c.decode(String.self, forKey: .id)
        query = (try? c.decode(String.self, forKey: .query)) ?? "(sem título)"
        category = try? c.decode(String.self, forKey: .category)
        source_count = try? c.decode(Int.self, forKey: .source_count)
        status = try? c.decode(String.self, forKey: .status)
        phase = try? c.decode(String.self, forKey: .phase)
        rounds = try? c.decode(Int.self, forKey: .rounds)
        duration = try? c.decode(String.self, forKey: .duration)
        started_at = try? c.decode(Double.self, forKey: .started_at)
        completed_at = try? c.decode(Double.self, forKey: .completed_at)
        archived = try? c.decode(Bool.self, forKey: .archived)
    }
}

extension APIClient {
    /// Starts a deep research run. `maxRounds == nil` lets the agent decide (Auto).
    func startResearch(query: String, maxRounds: Int?, category: String? = nil) async throws -> String {
        var body: [String: Any] = ["query": query]
        if let maxRounds { body["max_rounds"] = maxRounds }
        if let category, category != "auto" { body["category"] = category }
        var req = request("/api/research/start", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(req)
        return try decode(ResearchStart.self, data).session_id
    }

    /// Running jobs. `GET /api/research/active`.
    func activeResearch() async throws -> [ResearchJob] {
        decodeList(ResearchJob.self, try await send(request("/api/research/active")))
    }

    /// Past research, most-recent first. `GET /api/research/library`.
    func researchLibrary(limit: Int = 20) async throws -> [ResearchJob] {
        decodeList(ResearchJob.self, try await send(request("/api/research/library?sort=recent&limit=\(limit)")))
    }

    /// URL of a research's rendered visual report. `GET /api/research/report/{id}`.
    func researchReportURL(_ id: String) -> URL { config.url("/api/research/report/\(id)") }

    /// Raw HTML of the visual report, parsed natively by `ReportParser`.
    func researchReportHTML(_ id: String) async throws -> String {
        var req = request("/api/research/report/\(encPath(id))")
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        let data = try await send(req)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Streams `ResearchEvent`s from the SSE endpoint until `final`/done/error.
    func researchStream(_ id: String) -> AsyncThrowingStream<ResearchEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = request("/api/research/stream/\(encPath(id))")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.timeoutInterval = 600
                    let (bytes, resp) = try await session.bytes(for: req)
                    if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw APIError.http(http.statusCode, nil)
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty || payload == "[DONE]" { continue }
                        if let d = payload.data(using: .utf8),
                           let evt = try? JSONDecoder().decode(ResearchEvent.self, from: d) {
                            continuation.yield(evt)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
