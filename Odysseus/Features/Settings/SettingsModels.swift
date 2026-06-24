import Foundation

/// A model-serving endpoint the user has connected (local server or cloud API),
/// from `GET /api/model-endpoints`.
struct ModelEndpoint: Decodable, Identifiable, Hashable {
    let id: String
    var name: String
    var isEnabled: Bool
    var online: Bool?
    var url: String?
    var isLocal: Bool
    var models: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, url, models, online
        case isEnabled = "is_enabled"
        case kind, type, is_local
        case base_url, endpoint_url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "—"
        isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? true
        online = try? c.decodeIfPresent(Bool.self, forKey: .online)
        let u = (try? c.decodeIfPresent(String.self, forKey: .url))
            ?? (try? c.decodeIfPresent(String.self, forKey: .base_url))
            ?? (try? c.decodeIfPresent(String.self, forKey: .endpoint_url)) ?? nil
        url = u
        if let l = try? c.decodeIfPresent(Bool.self, forKey: .is_local) {
            isLocal = l
        } else {
            let kind = ((try? c.decodeIfPresent(String.self, forKey: .kind))
                ?? (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "").lowercased()
            // Heuristic: a private-network / loopback host is a local server.
            let host = (u ?? "").lowercased()
            let localHost = host.contains("localhost") || host.contains("127.0.0.1")
                || host.contains("192.168.") || host.contains("10.0.")
                || host.contains("://10.") || host.contains("172.16.") || host.contains(".local")
            isLocal = kind.contains("local") || localHost
        }
        // models may be [String] or [{id|name}]
        if let s = try? c.decode([String].self, forKey: .models) {
            models = s
        } else if let objs = try? c.decode([ModelRef].self, forKey: .models) {
            models = objs.compactMap { $0.id ?? $0.name }
        } else {
            models = []
        }
    }

    private struct ModelRef: Decodable { var id: String?; var name: String? }
}

/// A read-only view over the server's key/value settings (`/api/auth/settings`).
struct SettingsBag {
    var dict: [String: Any]

    func string(_ k: String) -> String { (dict[k] as? String) ?? "" }
    func int(_ k: String, default d: Int = 0) -> Int {
        if let i = dict[k] as? Int { return i }
        if let s = dict[k] as? String, let i = Int(s) { return i }
        return d
    }
    func bool(_ k: String, default d: Bool = false) -> Bool { (dict[k] as? Bool) ?? d }

    /// `[{endpoint_id, model}]` fallback chains.
    func fallbacks(_ k: String) -> [(endpointId: String, model: String)] {
        (dict[k] as? [[String: Any]])?.map {
            (endpointId: ($0["endpoint_id"] as? String) ?? "", model: ($0["model"] as? String) ?? "")
        } ?? []
    }
}
