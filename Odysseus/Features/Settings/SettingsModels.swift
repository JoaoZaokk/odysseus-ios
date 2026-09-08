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
    /// The *visible* models — hidden and unpinned ones are not here.
    var models: [String]
    /// The server's inventory total, hidden ones included. nil on an older
    /// server; the row then falls back to `models.count`.
    var modelCount: Int?
    var modelType: String?

    var total: Int { modelCount ?? models.count }
    var isImage: Bool { modelType == "image" }

    enum CodingKeys: String, CodingKey {
        case id, name, url, models, online
        case isEnabled = "is_enabled"
        case kind, type, is_local
        case base_url, endpoint_url
        case modelCount = "model_count"
        case modelType = "model_type"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A numeric id decodes too — the sibling models (Note, GalleryImage,
        // EmailAccount, ChatSession) all carry this branch. Without it the row
        // gets a client-invented UUID, and every button on it addresses nothing.
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) }
        else { id = UUID().uuidString }
        name = (try? c.decode(String.self, forKey: .name)) ?? "—"
        isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? true
        online = try? c.decodeIfPresent(Bool.self, forKey: .online)
        modelCount = try? c.decodeIfPresent(Int.self, forKey: .modelCount)
        modelType = try? c.decodeIfPresent(String.self, forKey: .modelType)
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

/// `POST /api/{copilot|chatgpt-subscription}/device/start`.
struct DeviceFlowStart: Decodable {
    let pollId: String
    let userCode: String
    let verificationURI: String?
    let verificationURIComplete: String?
    let interval: Int?
    let expiresIn: Int?
    enum CodingKeys: String, CodingKey {
        case pollId = "poll_id", userCode = "user_code", verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete", interval, expiresIn = "expires_in"
    }
    var authURL: URL? { URL(string: verificationURIComplete ?? verificationURI ?? "") }
    var step: TimeInterval { max(Double(interval ?? 5), 2) }
}

/// `POST …/device/poll`: pending | authorized (+endpoint) | failed (+error).
struct DeviceFlowPoll: Decodable {
    struct Endpoint: Decodable {
        let id: String
        let name: String?
        let models: [String]
        enum CodingKeys: String, CodingKey { case id, name, models }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            if let s = try? c.decode(String.self, forKey: .id) { id = s }
            else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) } else { id = "" }
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            models = (try? c.decode([String].self, forKey: .models)) ?? []
        }
    }
    let status: String
    let error: String?
    let detail: String?
    let endpoint: Endpoint?
}

/// What `POST /api/model-endpoints` answers: the probe of the host just added.
struct EndpointProbe: Decodable {
    var status: String?
    var online: Bool?
    var models: [String]
    var pingError: String?

    var isOnline: Bool { status == "online" || (status == nil && online == true) }

    enum CodingKeys: String, CodingKey { case status, online, models, pingError = "ping_error" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        online = try? c.decodeIfPresent(Bool.self, forKey: .online)
        pingError = try? c.decodeIfPresent(String.self, forKey: .pingError)
        if let s = try? c.decode([String].self, forKey: .models) { models = s }
        else if let objs = try? c.decode([[String: String]].self, forKey: .models) { models = objs.compactMap { $0["id"] ?? $0["name"] } }
        else { models = [] }
    }
}

/// One model discovered on an endpoint, from `GET /api/model-endpoints/{id}/models`.
struct EndpointModel: Decodable, Identifiable, Hashable {
    let id: String
    var display: String
    var isHidden: Bool
    var isPinned: Bool
    /// The server keeps two lists and only one applies per endpoint: cloud
    /// ("api") endpoints are allow-lists driven by `pinned_models`, local ones
    /// are deny-lists driven by `hidden_models`. This flag says which, so a
    /// model's visibility reads from `isPinned` on the former and `!isHidden`
    /// on the latter. Older servers omit it — false keeps the deny-list path.
    var pickerRequiresPinning: Bool

    enum CodingKeys: String, CodingKey {
        case id, display
        case isHidden = "is_hidden"
        case isPinned = "is_pinned"
        case pickerRequiresPinning = "picker_requires_pinning"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A numeric id decodes too — the sibling models (Note, GalleryImage,
        // EmailAccount, ChatSession) all carry this branch. Without it the row
        // gets a client-invented UUID, and every button on it addresses nothing.
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) }
        else { id = UUID().uuidString }
        display = (try? c.decode(String.self, forKey: .display)) ?? id
        isHidden = (try? c.decode(Bool.self, forKey: .isHidden)) ?? false
        isPinned = (try? c.decode(Bool.self, forKey: .isPinned)) ?? false
        pickerRequiresPinning = (try? c.decode(Bool.self, forKey: .pickerRequiresPinning)) ?? false
    }

    /// Whether the model picker offers this model.
    var isVisible: Bool { pickerRequiresPinning ? isPinned : !isHidden }
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
    /// A numeric setting as field text, or `""` when the server has no such key.
    /// `int(_:)` would answer 0, which renders as a real value the user then saves
    /// back as configuration; empty lets the field show its placeholder instead,
    /// and `save` skips keys whose text is not a number.
    func intText(_ k: String) -> String {
        if let i = dict[k] as? Int { return String(i) }
        if let s = dict[k] as? String, Int(s) != nil { return s }
        return ""
    }

    /// `[{endpoint_id, model}]` fallback chains.
    func fallbacks(_ k: String) -> [(endpointId: String, model: String)] {
        (dict[k] as? [[String: Any]])?.map {
            (endpointId: ($0["endpoint_id"] as? String) ?? "", model: ($0["model"] as? String) ?? "")
        } ?? []
    }
}
