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

    /// Creates a model endpoint. `kind` is "local" or "api". The server probes
    /// the `base_url` and auto-discovers the model list (`model_refresh_mode`).
    func createEndpoint(name: String, baseURL: String, apiKey: String?, kind: String) async throws {
        // The endpoint reads `Form(...)` fields, not JSON — send form-urlencoded.
        var fields = [
            "name": name,
            "base_url": baseURL,
            "model_type": "llm",
            "endpoint_kind": kind,
            "category": kind,
        ]
        if let apiKey, !apiKey.isEmpty { fields["api_key"] = apiKey }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = fields.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&")
        var req = request("/api/model-endpoints", method: "POST")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = encoded.data(using: .utf8)
        _ = try await send(req)
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

    func twoFAEnabled() async throws -> Bool {
        let data = try await send(request("/api/auth/2fa/status"))
        let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (dict["enabled"] as? Bool) ?? false
    }
}
