import Foundation

extension APIClient {
    /// Whole settings object (key/value). `/api/auth/settings`.
    func getSettings() async throws -> SettingsBag {
        let data = try await send(request("/api/auth/settings"))
        let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return SettingsBag(dict: dict)
    }

    /// Merge-saves a partial settings payload (server merges into the stored object).
    func saveSettings(_ partial: [String: Any]) async throws {
        var req = request("/api/auth/settings", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: partial)
        _ = try await send(req)
    }

    /// Connected model endpoints. `/api/model-endpoints`.
    func modelEndpoints() async throws -> [ModelEndpoint] {
        decodeList(ModelEndpoint.self, try await send(request("/api/model-endpoints")))
    }

    /// Re-probes an endpoint and rewrites its cached model list.
    ///
    /// `GET /api/model-endpoints` is cache-only server-side: it never probes, so
    /// an endpoint added while its backend was unreachable reports zero models
    /// forever and the model picker stays empty. This is the only way to heal it.
    /// Admin-only — the server answers 403 to everyone else.
    ///
    /// Rides `streamSession`: the server probes the backend inline and can take
    /// far longer than the default session's 30s whole-transfer cap.
    @discardableResult
    func refreshEndpointModels(_ id: String) async throws -> [EndpointModel] {
        let req = request("/api/model-endpoints/\(encPath(id))/models?refresh=true")
        return decodeList(EndpointModel.self, try await send(req, via: streamSession))
    }

    /// Every model discovered on an endpoint, with its per-model visibility.
    /// Unlike `refreshEndpointModels` this never probes the backend — it reads
    /// the cached list, so it is fast. Admin-only (403 for everyone else).
    func endpointModels(_ id: String) async throws -> [EndpointModel] {
        decodeList(EndpointModel.self, try await send(request("/api/model-endpoints/\(encPath(id))/models")))
    }

    /// Rewrites which of an endpoint's models the picker offers.
    ///
    /// Two shapes, one per endpoint kind (see `EndpointModel.pickerRequiresPinning`):
    /// an allow-list of visible ids for cloud APIs, a deny-list of hidden ids
    /// for local servers. Sending the wrong one is not an error server-side —
    /// it silently converts — but the allow-list is written from the cached
    /// model list only, which would drop pinned ids the backend never listed.
    func setEndpointModelVisibility(_ id: String, visible: [String], hidden: [String],
                                    pinning: Bool) async throws {
        var req = request("/api/model-endpoints/\(encPath(id))/models", method: "PATCH")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = pinning ? ["pinned_models": visible] : ["hidden": hidden]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await send(req)
    }

    /// Creates a model endpoint. `kind` is "local", "api" or "image". The
    /// server probes `base_url` and answers with the probe — `status`,
    /// `models`, `ping_error` — which 1.8 threw away and reported as
    /// "Adicionado" whether the host answered or not.
    ///
    /// `model_type` is always sent: the server overwrites an existing row's
    /// type with the incoming value (default "llm"), so re-adding an image
    /// endpoint without saying so demoted it.
    func createEndpoint(name: String, baseURL: String, apiKey: String?, kind: String) async throws -> EndpointProbe {
        // The endpoint reads `Form(...)` fields, not JSON — send form-urlencoded.
        var fields = [
            "name": name,
            "base_url": baseURL,
            "model_type": kind == "image" ? "image" : "llm",
            "endpoint_kind": kind == "image" ? "auto" : kind,
        ]
        if let apiKey, !apiKey.isEmpty { fields["api_key"] = apiKey }
        return try decode(EndpointProbe.self, try await send(formRequest("/api/model-endpoints", fields: fields)))
    }

    /// Enable/disable an endpoint (best-effort: PATCH the endpoint's is_enabled).
    func setEndpointEnabled(_ id: String, _ enabled: Bool) async throws {
        var req = request("/api/model-endpoints/\(encPath(id))", method: "PATCH")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["is_enabled": enabled])
        _ = try await send(req)
    }

    func deleteEndpoint(_ id: String) async throws {
        _ = try await send(request("/api/model-endpoints/\(encPath(id))", method: "DELETE"))
    }

    func changePassword(current: String, new: String) async throws {
        struct Body: Encodable { let current_password: String; let new_password: String }
        let req = try jsonRequest("/api/auth/change-password", method: "POST",
                                  body: Body(current_password: current, new_password: new))
        _ = try await send(req)
    }

    struct TwoFASetup { let secret: String; let uri: String; let qrPNG: Data? }

    /// `{secret, uri, qr_code: "data:image/png;base64,…"}`.
    func twoFASetup() async throws -> TwoFASetup {
        let data = try await send(request("/api/auth/2fa/setup", method: "POST"))
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let secret = d["secret"] as? String, !secret.isEmpty else { throw APIError.decoding("2fa secret ausente") }
        var png: Data?
        if let dataURL = d["qr_code"] as? String, let comma = dataURL.firstIndex(of: ",") {
            png = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
        }
        return TwoFASetup(secret: secret, uri: (d["uri"] as? String) ?? "", qrPNG: png)
    }

    /// Returns the backup codes; a wrong code is a 400 the caller shows.
    func twoFAConfirm(code: String) async throws -> [String] {
        struct B: Encodable { let code: String }
        let data = try await send(try jsonRequest("/api/auth/2fa/confirm", method: "POST", body: B(code: code)))
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (d["backup_codes"] as? [String]) ?? []
    }

    func twoFADisable(password: String) async throws {
        struct B: Encodable { let password: String }
        _ = try await send(try jsonRequest("/api/auth/2fa/disable", method: "POST", body: B(password: password)))
    }

    // Device flow (GitHub Copilot / ChatGPT Subscription). All form posts;
    // `provider` is an enum raw value, never user input.
    func deviceFlowStart(_ provider: String) async throws -> DeviceFlowStart {
        try decode(DeviceFlowStart.self, try await send(formRequest("/api/\(provider)/device/start", fields: [:])))
    }
    func deviceFlowPoll(_ provider: String, pollId: String) async throws -> DeviceFlowPoll {
        try decode(DeviceFlowPoll.self, try await send(formRequest("/api/\(provider)/device/poll", fields: ["poll_id": pollId])))
    }
    func deviceFlowCancel(_ provider: String, pollId: String) async {
        _ = try? await send(formRequest("/api/\(provider)/device/cancel", fields: ["poll_id": pollId]))
    }

    struct SearchTestResult { let count: Int; let ms: Int; let top: String }
    /// `POST /api/search/query` reports failures inside a 200.
    func searchTest(provider: String, query: String = "hello world", count: Int = 3) async throws -> SearchTestResult {
        let t0 = Date()
        let data = try await send(formRequest("/api/search/query", fields: ["query": query, "provider": provider, "count": String(count)]))
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let e = d["error"] as? String, !e.isEmpty { throw APIError.transport(e) }
        let results = (d["results"] as? [[String: Any]]) ?? []
        let top = (results.first?["title"] as? String) ?? (results.first?["url"] as? String) ?? ""
        return SearchTestResult(count: results.count, ms: Int(Date().timeIntervalSince(t0) * 1000), top: top)
    }

    func twoFAEnabled() async throws -> Bool {
        let data = try await send(request("/api/auth/2fa/status"))
        let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (dict["enabled"] as? Bool) ?? false
    }
}
