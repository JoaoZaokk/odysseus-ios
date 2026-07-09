import Foundation

/// Options that map to the chat_stream FormData flags the web client sends.
struct ChatStreamOptions {
    var mode: String = "chat"          // "chat" | "agent"
    var webSearch: Bool = false
    var research: Bool = false         // deep research
    var attachmentIDs: [String] = []
}

/// Streams a reply from POST /api/chat_stream. The endpoint returns Server-Sent
/// Events: newline-delimited `data: {json}` frames terminated by `data: [DONE]`.
final class ChatStreamClient: @unchecked Sendable {
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func send(message: String, sessionID: String, options: ChatStreamOptions) -> AsyncThrowingStream<ChatStreamUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let req = buildRequest(message: message, sessionID: sessionID, options: options)
                    let (bytes, resp) = try await api.streamSession.bytes(for: req)

                    if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        if http.statusCode == 401 || http.statusCode == 403 {
                            throw APIError.notAuthenticated
                        }
                        // Drain a little of the body for an error message.
                        var body = ""
                        for try await line in bytes.lines { body += line; if body.count > 500 { break } }
                        throw APIError.http(http.statusCode, Self.extractError(body) ?? "Falha ao iniciar o stream")
                    }

                    var sawError = false
                    for try await rawLine in bytes.lines {
                        if Task.isCancelled { break }
                        let line = rawLine

                        if line.hasPrefix("event: ") {
                            if line.dropFirst(7).trimmingCharacters(in: .whitespaces) == "error" { sawError = true }
                            continue
                        }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" {
                            continuation.yield(.done)
                            break
                        }

                        guard let data = payload.data(using: .utf8),
                              let evt = try? JSONDecoder().decode(StreamEvent.self, from: data) else {
                            continue
                        }

                        if sawError || (evt.status ?? 0) >= 400 {
                            continuation.yield(.error(evt.errorMessage ?? "Erro no stream"))
                            break
                        }

                        if let delta = evt.delta, !delta.isEmpty {
                            if evt.thinking == true { continuation.yield(.thinkingDelta(delta)) }
                            else { continuation.yield(.textDelta(delta)) }
                            continue
                        }

                        switch evt.type {
                        case "tool_start":
                            if let n = evt.toolName { continuation.yield(.toolStart(n)) }
                        case "model_info", "model_actual":
                            if let m = evt.modelName { continuation.yield(.modelResolved(m)) }
                        case "research_progress":
                            continuation.yield(.toolStart(evt.text ?? "deep_research"))
                        default:
                            break   // doc/rag/metrics/sources events ignored in MVP
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

    // MARK: - Request

    private func buildRequest(message: String, sessionID: String, options: ChatStreamOptions) -> URLRequest {
        var req = URLRequest(url: api.config.url("/api/chat_stream"))
        req.httpMethod = "POST"
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 300

        let tz = TimeZone.current
        req.setValue(String(-tz.secondsFromGMT() / 60), forHTTPHeaderField: "X-Tz-Offset")
        req.setValue(tz.identifier, forHTTPHeaderField: "X-Tz-Name")

        var fields: [String: String] = [
            "message": message,
            "session": sessionID,
            "mode": options.mode,
        ]
        if options.research {
            fields["use_research"] = "true"
        } else if options.webSearch {
            fields["allow_web_search"] = "true"
            fields["use_web"] = "true"
        }
        var form = MultipartForm(fields: fields)
        if !options.attachmentIDs.isEmpty,
           let json = try? JSONSerialization.data(withJSONObject: options.attachmentIDs),
           let s = String(data: json, encoding: .utf8) {
            form.append(field: "attachments", value: s)
        }
        req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = form.finalizedData
        return req
    }

    private static func extractError(_ body: String) -> String? {
        guard let r = body.range(of: "\"message\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) else {
            return body.count < 200 ? body : nil
        }
        return String(body[r]).replacingOccurrences(of: "\\\"", with: "\"")
    }
}
