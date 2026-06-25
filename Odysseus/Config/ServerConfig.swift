import Foundation

/// Where the Odysseus server lives. Persisted in UserDefaults so the user can
/// point the app at a different host (e.g. once it's exposed over HTTPS on the
/// public internet) without rebuilding.
struct ServerConfig: Equatable {
    var baseURL: URL

    static let defaultURLString = "https://odysseus.macrozao.online"

    private static let key = "odysseus.baseURL"

    static func load() -> ServerConfig {
        let stored = UserDefaults.standard.string(forKey: key) ?? defaultURLString
        return ServerConfig(baseURL: URL(string: stored) ?? URL(string: defaultURLString)!)
    }

    func save() {
        UserDefaults.standard.set(baseURL.absoluteString, forKey: Self.key)
    }

    /// Normalizes user input ("meu-servidor:7000", "chat.me") into a URL. With no
    /// scheme we pick one by host: local addresses (localhost, LAN IPs, *.local)
    /// are plain **http**; everything else defaults to **https**.
    static func normalize(_ input: String) -> URL? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") {
            let bare = s.split(whereSeparator: { $0 == "/" || $0 == ":" }).first.map(String.init) ?? s
            let isLocal = bare == "localhost" || bare == "0.0.0.0" || bare.hasSuffix(".local")
                || bare.hasPrefix("127.") || bare.hasPrefix("10.") || bare.hasPrefix("192.168.")
            s = (isLocal ? "http://" : "https://") + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }

    func url(_ path: String) -> URL {
        // Use relative-URL resolution so query strings (?a=b&c=d) are preserved.
        // `appendingPathComponent` would percent-escape the `?` into the path
        // and produce a 404.
        let p = path.hasPrefix("/") ? path : "/" + path
        if let u = URL(string: p, relativeTo: baseURL)?.absoluteURL { return u }
        return baseURL.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path)
    }

    /// Resolves a possibly-relative resource path (e.g. an image `url` from the
    /// gallery) against the server base URL.
    func resolve(_ raw: String) -> URL? {
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }
}
