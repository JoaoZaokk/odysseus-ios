import Foundation
import Network

/// Where the Odysseus server lives. Persisted in UserDefaults so the user can
/// point the app at a different host (e.g. once it's exposed over HTTPS on the
/// public internet) without rebuilding.
struct ServerConfig: Equatable {
    var baseURL: URL

    /// Placeholder host — point the app at your own Odysseus server on first run
    /// (tap the server label on the login screen). Never hardcode a real host here.
    static let defaultURLString = "https://odysseus.example.com"

    private static let key = "odysseus.baseURL"

    static func load() -> ServerConfig {
        let stored = UserDefaults.standard.string(forKey: key) ?? defaultURLString
        return ServerConfig(baseURL: URL(string: stored) ?? URL(string: defaultURLString)!)
    }

    func save() {
        UserDefaults.standard.set(baseURL.absoluteString, forKey: Self.key)
    }

    /// Only these schemes are ever accepted (no file://, ftp://, data:, custom…).
    static let allowedSchemes: Set<String> = ["http", "https"]

    /// True only for genuine loopback / link-local / RFC-1918 hosts, *.local, or
    /// localhost. Parses real IP literals so a *public* name like `10.evil.com`
    /// (which `hasPrefix("10.")` wrongly matched) is NOT treated as local and
    /// therefore never downgraded to cleartext http.
    static func isLocalHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h == "0.0.0.0" || h.hasSuffix(".local") { return true }
        if let v4 = IPv4Address(h) {
            let b = [UInt8](v4.rawValue)            // 4 bytes, network order
            guard b.count == 4 else { return false }
            switch b[0] {
            case 127: return true                              // 127.0.0.0/8 loopback
            case 10: return true                               // 10.0.0.0/8
            case 169: return b[1] == 254                       // 169.254.0.0/16 link-local
            case 172: return (16...31).contains(Int(b[1]))     // 172.16.0.0/12
            case 192: return b[1] == 168                       // 192.168.0.0/16
            default: return false
            }
        }
        if let v6 = IPv6Address(h) {
            if v6 == IPv6Address("::1") { return true }         // loopback
            let first = [UInt8](v6.rawValue).first ?? 0
            return (first & 0xfe) == 0xfc                       // fc00::/7 unique-local
        }
        return false
    }

    /// Normalizes user input ("meu-servidor:7000", "chat.me") into a URL. With no
    /// scheme we pick one by host: real local addresses are plain **http**;
    /// everything else defaults to **https**. Rejects non-http(s) schemes.
    static func normalize(_ input: String) -> URL? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") {
            let bare = s.split(whereSeparator: { $0 == "/" || $0 == ":" }).first.map(String.init) ?? s
            s = (isLocalHost(bare) ? "http://" : "https://") + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), let host = url.host, !host.isEmpty,
              let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else { return nil }
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
        let url = (raw.hasPrefix("http://") || raw.hasPrefix("https://"))
            ? URL(string: raw)
            : URL(string: raw, relativeTo: baseURL)?.absoluteURL
        // Never hand back a non-http(s) URL (blocks file://, data:, etc. smuggled
        // through a server-supplied image/resource path).
        guard let u = url, let scheme = u.scheme?.lowercased(),
              Self.allowedSchemes.contains(scheme) else { return nil }
        return u
    }
}
