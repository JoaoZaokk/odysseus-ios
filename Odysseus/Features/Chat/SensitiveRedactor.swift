import Foundation

/// The web's `censor.js` pass 1, ported: does this text carry something
/// that should not sit on screen in a café — an email address, an API key,
/// a bearer token, a `password: …` pair, a card or SSN-shaped number?
enum SensitiveRedactor {
    private static let patterns: [NSRegularExpression] = {
        let specs: [(String, NSRegularExpression.Options)] = [
            (#"\b[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}\b"#, []),
            (#"\b(sk-[a-zA-Z0-9]{20,}|pk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36,}|gho_[a-zA-Z0-9]{36,}|glpat-[a-zA-Z0-9\-_]{20,}|xox[bpras]-[a-zA-Z0-9\-]{10,}|npm_[a-zA-Z0-9]{36,}|AKIA[A-Z0-9]{12,})\b"#, []),
            (#"Bearer\s+[A-Za-z0-9._\-]{20,}"#, []),
            (#"(?:password|passwd|secret|api[_\-]?key|access[_\-]?token|auth[_\-]?token|private[_\-]?key|client[_\-]?secret)[\s]*[:=]\s*["']?[^\s"'<]{4,}["']?"#, [.caseInsensitive]),
            (#"\b(?:\d[ -]?){13,19}\b"#, []),
            (#"\b\d{3}-\d{2}-\d{4}\b"#, []),
        ]
        return specs.compactMap { try? NSRegularExpression(pattern: $0.0, options: $0.1) }
    }()

    static func hasSensitive(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return patterns.contains { $0.firstMatch(in: text, range: range) != nil }
    }
}
