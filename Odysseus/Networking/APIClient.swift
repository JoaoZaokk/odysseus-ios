import Foundation

enum APIError: LocalizedError {
    case http(Int, String?)
    case notAuthenticated
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let msg): return msg ?? "Erro \(code)"
        case .notAuthenticated: return "Sessão expirada. Faça login novamente."
        case .decoding(let m): return "Resposta inesperada do servidor: \(m)"
        case .transport(let m): return m
        }
    }
}

/// Talks to the Odysseus REST API. Auth is cookie-based: a successful login sets
/// a session cookie that `URLSession` persists (HTTPCookieStorage) and replays
/// on every subsequent request — including the streaming endpoint.
final class APIClient: @unchecked Sendable {
    private(set) var config: ServerConfig
    let session: URLSession

    init(config: ServerConfig) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = .shared
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 30   // cap the whole request — never hang forever
        cfg.waitsForConnectivity = false      // fail fast with an error instead of waiting endlessly
        self.session = URLSession(configuration: cfg)
    }

    func updateConfig(_ config: ServerConfig) { self.config = config }

    // MARK: - Request helpers (internal so feature extensions can reuse them)

    func request(_ path: String, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: config.url(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    /// Percent-encodes a value for safe use as a single URL **path segment** (also
    /// escapes `/ ? #`). Server-supplied ids (email uid, session/research/gallery id)
    /// must go through this so a malicious id can't smuggle path/query separators.
    func encPath(_ s: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
    /// Percent-encodes a value for safe use as a URL **query value** (escapes `& = ? #`).
    func encQuery(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?#")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// POST/PUT with a JSON body.
    func jsonRequest(_ path: String, method: String, body: Encodable) throws -> URLRequest {
        var req = request(path, method: method)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        return req
    }

    @discardableResult
    func send(_ req: URLRequest) async throws -> Data {
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return data }
            if http.statusCode == 401 || http.statusCode == 403 { throw APIError.notAuthenticated }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.http(http.statusCode, Self.detail(from: data))
            }
            return data
        } catch let e as APIError {
            throw e
        } catch {
            // A request cancelled by a view transition (.task teardown) should
            // not surface as a user-facing error.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw APIError.transport(error.localizedDescription)
        }
    }

    func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decoding(String(describing: error)) }
    }

    /// Decodes either a bare `[T]` array or a single-key wrapper object whose
    /// value is the array (e.g. `{ "memories": [...] }`). Many Odysseus list
    /// endpoints use one or the other.
    func decodeList<T: Decodable>(_ type: T.Type, _ data: Data) -> [T] {
        if let arr = try? JSONDecoder().decode([T].self, from: data) { return arr }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for v in obj.values {
                if let inner = v as? [Any],
                   let d = try? JSONSerialization.data(withJSONObject: inner),
                   let arr = try? JSONDecoder().decode([T].self, from: d) {
                    return arr
                }
            }
        }
        return []
    }

    private static func detail(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Cap a non-JSON body (a hostile server could return MBs → soft DoS in Text).
            return String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : String($0.prefix(500)) }
        }
        // FastAPI validation errors put an array under `detail`:
        // [{ loc: ["body","field"], msg: "field required", ... }]
        if let arr = obj["detail"] as? [[String: Any]] {
            let msgs = arr.compactMap { e -> String? in
                let field = (e["loc"] as? [Any])?.compactMap { "\($0)" }.last { $0 != "body" }
                let msg = e["msg"] as? String
                switch (field, msg) {
                case let (f?, m?): return "\(f): \(m)"
                case let (_, m?):  return m
                default:           return nil
                }
            }
            if !msgs.isEmpty { return msgs.joined(separator: " · ") }
        }
        return obj["detail"] as? String ?? obj["message"] as? String ?? obj["error"] as? String
    }

    // MARK: - Auth

    func status() async throws -> AuthStatus {
        try decode(AuthStatus.self, try await send(request("/api/auth/status")))
    }

    func features() async throws -> Features {
        (try? decode(Features.self, try await send(request("/api/auth/features")))) ?? Features()
    }

    /// POST /api/auth/login  — returns true on success, throws with a message on
    /// failure. Sets `.totpRequired` via the thrown sentinel when 2FA is needed.
    @discardableResult
    func login(username: String, password: String, remember: Bool, totp: String? = nil) async throws -> LoginResponse {
        var req = request("/api/auth/login", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            LoginRequest(username: username, password: password, remember: remember, totp_code: totp)
        )
        // We don't use `send` here because we want to inspect the body even on
        // non-2xx (to detect 2FA prompts vs. bad credentials).
        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        let parsed = (try? JSONDecoder().decode(LoginResponse.self, from: data)) ?? LoginResponse.empty
        if let code = http?.statusCode, !(200..<300).contains(code) {
            if parsed.totpRequired == true { return parsed }   // not an error: prompt for code
            throw APIError.http(code, parsed.detail ?? Self.detail(from: data))
        }
        return parsed
    }

    func logout() async {
        // The web app clears the session via the same cookie store; a GET to
        // /logout (or DELETE) invalidates it server-side. Best-effort.
        _ = try? await session.data(for: request("/logout"))
        if let url = config.baseURL.host.flatMap({ _ in config.baseURL }),
           let cookies = HTTPCookieStorage.shared.cookies(for: url) {
            cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }
    }

    // MARK: - Sessions

    func sessions() async throws -> [ChatSession] {
        let data = try await send(request("/api/sessions"))
        if let arr = try? JSONDecoder().decode([ChatSession].self, from: data) { return arr }
        // Or wrapped: { sessions: [...] }
        struct Wrap: Decodable { let sessions: [ChatSession] }
        if let w = try? JSONDecoder().decode(Wrap.self, from: data) { return w.sessions }
        return []
    }

    func history(_ sessionID: String) async throws -> SessionDetail {
        try decode(SessionDetail.self, try await send(request("/api/history/\(encPath(sessionID))")))
    }

    func defaultChat() async throws -> DefaultChat {
        try decode(DefaultChat.self, try await send(request("/api/default-chat")))
    }

    /// /api/models is grouped by endpoint: `{items:[{url, endpoint_id, models:[id,...]}]}`.
    /// We flatten into a single list of selectable models.
    func models() async throws -> [ChatModel] {
        let data = try await send(request("/api/models"))
        struct Group: Decodable {
            var url: String?
            var endpoint_id: String?
            var models: [String]
        }
        struct Wrap: Decodable { var items: [Group] }
        guard let wrap = try? JSONDecoder().decode(Wrap.self, from: data) else {
            // Fall back to a bare list of {id,name} just in case.
            return decodeList(ChatModel.self, data)
        }
        return wrap.items.flatMap { group in
            group.models.map { id in
                ChatModel(id: id,
                          name: id.split(separator: "/").last.map(String.init) ?? id,
                          endpointId: group.endpoint_id,
                          endpointURL: group.url)
            }
        }
    }

    /// Creates a session for the given default-chat config and returns its id.
    func createSession(from dc: DefaultChat, name: String) async throws -> String {
        var fields: [String: String] = [
            "name": name,
            "endpoint_url": dc.endpointURL,
            "model": dc.model,
            "skip_validation": "true",
        ]
        if let eid = dc.endpointID { fields["endpoint_id"] = eid }
        var req = request("/api/session", method: "POST")
        let body = MultipartForm(fields: fields)
        req.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = body.finalizedData
        let created = try decode(CreateSessionResponse.self, try await send(req))
        guard !created.id.isEmpty else { throw APIError.decoding("session id ausente") }
        return created.id
    }

    func deleteSession(_ id: String) async throws {
        _ = try await send(request("/api/session/\(encPath(id))", method: "DELETE"))
    }

    func renameSession(_ id: String, to name: String) async throws {
        var req = request("/api/session/\(encPath(id))", method: "PATCH")
        let body = MultipartForm(fields: ["name": name])
        req.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = body.finalizedData
        _ = try await send(req)
    }

    func stop(_ sessionID: String) async {
        _ = try? await session.data(for: request("/api/chat/stop/\(encPath(sessionID))", method: "POST"))
    }
}

private extension LoginResponse {
    /// Decoded from an empty object so the custom decoder fills defaults.
    static var empty: LoginResponse {
        (try? JSONDecoder().decode(LoginResponse.self, from: Data("{}".utf8)))!
    }
}

/// Builds a `multipart/form-data` body for the FormData endpoints
/// (POST /api/session, PATCH rename, and chat_stream's text fields).
struct MultipartForm {
    let boundary = "----OdysseusBoundary\(UUID().uuidString)"
    private(set) var data = Data()

    init(fields: [String: String] = [:]) {
        for (k, v) in fields { append(field: k, value: v) }
    }

    mutating func append(field name: String, value: String) {
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        data.append("\(value)\r\n")
    }

    mutating func append(file name: String, filename: String, mime: String, fileData: Data) {
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        data.append("Content-Type: \(mime)\r\n\r\n")
        data.append(fileData)
        data.append("\r\n")
    }

    /// Finalized body with the closing boundary.
    var finalizedData: Data {
        var d = data
        d.append("--\(boundary)--\r\n")
        return d
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }
}

private extension Data {
    mutating func append(_ s: String) { append(Data(s.utf8)) }
}

/// Type-erased Encodable so `jsonRequest` can take any Encodable body.
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
