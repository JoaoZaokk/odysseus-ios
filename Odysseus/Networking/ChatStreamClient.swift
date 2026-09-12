import Foundation

/// Options that map to the chat_stream FormData flags the web client sends.
struct ChatStreamOptions {
    var mode: String = "chat"          // "chat" | "agent"
    var webSearch: Bool = false
    var research: Bool = false         // deep research
    var attachmentIDs: [String] = []
    /// Model route picked in the composer, reconciled server-side before the
    /// reply is generated (and persisted onto the session). The server only
    /// trusts a route it can resolve to a registered endpoint, so the id/URL
    /// travel with the model — sending the model alone is a no-op.
    var model: ChatModel?
    /// Answer to a `kind: "tool_approval"` card. The server replays the sealed
    /// action it had held back, so this turn carries no user message at all —
    /// it is a control-plane continuation, not a new question.
    var approval: (id: String, decision: String)?
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
                        if http.statusCode == 401 {
                            api.onUnauthenticated?()
                            throw APIError.notAuthenticated
                        }
                        // Drain a little of the body for an error message.
                        var body = ""
                        for try await line in bytes.lines { body += line; if body.count > 500 { break } }
                        throw APIError.http(http.statusCode, Self.extractError(body) ?? "Falha ao iniciar o stream")
                    }

                    if let http = resp as? HTTPURLResponse,
                       let rid = http.value(forHTTPHeaderField: "X-Odysseus-Run-Id"), !rid.isEmpty {
                        continuation.yield(.runStarted(rid))
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
                        case "ask_user":
                            if let ask = evt.ask, ask.isRenderable { continuation.yield(.askUser(ask)) }
                        case "tool_approval_resolved":
                            // Only ever sent for a denial — an approval just
                            // continues into the reply stream.
                            if evt.decision == "deny" { continuation.yield(.notice(ChatNotice(kind: .approvalDenied))) }
                        default:
                            // Context trims and agent guards explain why the reply
                            // looks amnesiac or cut short — surface them.
                            if let n = evt.notice { continuation.yield(.notice(n)) }
                            // doc/rag/metrics/sources events still ignored.
                        }
                    }
                    continuation.finish()
                } catch let e where e.isCancellation {
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
        if let a = options.approval {
            fields["tool_approval_id"] = a.id
            fields["tool_approval_decision"] = a.decision
        }
        if let m = options.model {
            fields["selected_model"] = m.id
            if let eid = m.endpointId, !eid.isEmpty { fields["selected_endpoint_id"] = eid }
            if let url = m.endpointURL, !url.isEmpty { fields["selected_endpoint_url"] = url }
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

    /// Pulls the human message out of an HTTP error body. FastAPI's own errors
    /// are `{"detail": "…"}` (a string, or the 422 array of `{loc, msg}`); the
    /// server's four custom exceptions are `{"error": …, "message": "…"}`; a
    /// stream error frame is `{"error": "…"}`. 1.9 only looked for `message`,
    /// so the most common live error — "No model selected for this chat…" —
    /// reached the user as raw JSON.
    static func extractError(_ body: String) -> String? {
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let d = obj["detail"] as? String, !d.isEmpty { return d }
            if let arr = obj["detail"] as? [[String: Any]] {
                let msgs = arr.compactMap { $0["msg"] as? String }
                if !msgs.isEmpty { return msgs.joined(separator: "; ") }
            }
            if let m = obj["message"] as? String, !m.isEmpty { return m }
            if let e = obj["error"] as? String, !e.isEmpty { return e }
            if let e = obj["error"] as? [String: Any], let m = e["message"] as? String, !m.isEmpty { return m }
        }
        // Not JSON (a proxy's HTML, a truncated body): show it only if it is short
        // enough to be a sentence rather than a page.
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count < 200 && !trimmed.hasPrefix("{") && !trimmed.hasPrefix("<") ? trimmed : nil
    }
}
