import Foundation

/// A cloud API the server knows how to talk to, and how to recognise its key.
///
/// Adding one used to mean typing its base URL from memory: paste a Gemini key
/// into the form and nothing happened until
/// `https://generativelanguage.googleapis.com/v1beta/openai` was typed next to
/// it. The web offers the same list as a picker (`static/index.html`,
/// `adm-epProvider`) and fills the URL from the key's prefix
/// (`static/js/slashCommands.js`, `PROVIDER_PATTERNS`); this is the app's copy.
/// The two device-flow providers (Copilot, ChatGPT) are not here — they have
/// their own cards and no key.
struct ProviderPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let baseURL: String
    /// Key prefixes that name this provider unambiguously. "sk-" alone is not
    /// one: every OpenAI-compatible vendor uses it.
    var keyPrefixes: [String] = []

    static let all: [ProviderPreset] = [
        .init(id: "anthropic", name: "Anthropic", baseURL: "https://api.anthropic.com", keyPrefixes: ["sk-ant-"]),
        .init(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com/v1"),
        .init(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", keyPrefixes: ["sk-proj-"]),
        .init(id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", keyPrefixes: ["sk-or-"]),
        .init(id: "ollama-cloud", name: "Ollama Cloud", baseURL: "https://ollama.com/api"),
        .init(id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1", keyPrefixes: ["gsk_"]),
        .init(id: "mistral", name: "Mistral", baseURL: "https://api.mistral.ai/v1"),
        .init(id: "together", name: "Together AI", baseURL: "https://api.together.xyz/v1"),
        .init(id: "fireworks", name: "Fireworks AI", baseURL: "https://api.fireworks.ai/inference/v1"),
        .init(id: "gemini", name: "Google Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
              keyPrefixes: ["AIza"]),
        .init(id: "xai", name: "xAI Grok", baseURL: "https://api.x.ai/v1", keyPrefixes: ["xai-"]),
        .init(id: "zai", name: "Z.AI (Zhipu)", baseURL: "https://api.z.ai/api/paas/v4"),
        .init(id: "opencode-zen", name: "OpenCode Zen", baseURL: "https://opencode.ai/zen/v1"),
        .init(id: "opencode-go", name: "OpenCode Go", baseURL: "https://opencode.ai/zen/go/v1"),
        .init(id: "zai-coding", name: "Z.AI Coding Plan", baseURL: "https://api.z.ai/api/coding/paas/v4"),
        .init(id: "nvidia", name: "NVIDIA", baseURL: "https://integrate.api.nvidia.com/v1", keyPrefixes: ["nvapi-"]),
    ]

    /// The provider a pasted key belongs to, when its prefix says so.
    static func detect(key: String) -> ProviderPreset? {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return nil }
        return all.first { p in p.keyPrefixes.contains { k.hasPrefix($0) } }
    }

    /// The preset whose base URL this is, ignoring a trailing slash.
    static func matching(url: String) -> ProviderPreset? {
        let u = normalize(url)
        return all.first { $0.baseURL == u }
    }

    /// The web's `_normalizeBaseUrl`, with one difference: a bare public host
    /// gets **https**. The web prefixes http://, and the server does the same
    /// for a scheme-less URL — which for Google turns the native model listing
    /// into a plain-HTTP request that never returns a model list, so a valid
    /// key reads as a dead one. Local hosts keep http, as `ServerConfig` does.
    static func normalize(_ raw: String) -> String {
        var u = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { return u }
        // Scheme typos: "https:/host", "htps://", "http:///host".
        if let r = u.range(of: #"^(https?):/(?!/)"#, options: .regularExpression) {
            u.replaceSubrange(r, with: u[r].dropLast() + "//")
        }
        u = u.replacingOccurrences(of: #"^htp:"#, with: "http:", options: .regularExpression)
        u = u.replacingOccurrences(of: #"^htps:"#, with: "https:", options: .regularExpression)
        u = u.replacingOccurrences(of: #"^(https?)://+"#, with: "$1://", options: .regularExpression)
        if u.range(of: #"^https?://"#, options: .regularExpression) == nil {
            let host = String(u.split(separator: "/", maxSplits: 1).first ?? "")
            let bare = String(host.split(separator: ":").first ?? "")
            u = (ServerConfig.isLocalHost(bare) ? "http://" : "https://") + u
        }
        u = u.components(separatedBy: "?")[0].components(separatedBy: "#")[0]
        while u.hasSuffix("/") { u.removeLast() }
        u = u.replacingOccurrences(of: #"/v1/(models|chat/completions|completions|messages)$"#,
                                   with: "/v1", options: [.regularExpression, .caseInsensitive])
        u = u.replacingOccurrences(of: #"/(models|chat/completions|completions|v1/messages)$"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        u = u.replacingOccurrences(of: #"/api/(chat|tags|generate)$"#,
                                   with: "/api", options: [.regularExpression, .caseInsensitive])
        u = u.replacingOccurrences(of: #"/v1/v1$"#, with: "/v1", options: .regularExpression)
        return u
    }
}
