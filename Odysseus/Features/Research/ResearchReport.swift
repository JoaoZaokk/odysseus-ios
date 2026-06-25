import Foundation

// MARK: - Model

struct ResearchReport {
    var title: String
    var subtitle: String?
    var stats: [(label: String, value: String)]
    var blocks: [ReportBlock]
    var sources: [ReportSource]
}

enum ReportBlock: Identifiable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case image(url: String)
    case table(headers: [String], rows: [[String]])

    var id: String {
        switch self {
        case .heading(let l, let t): return "h\(l):\(t.prefix(24))"
        case .paragraph(let t): return "p:\(t.prefix(24))\(t.count)"
        case .image(let u): return "img:\(u)"
        case .table(let h, _): return "tbl:\(h.joined())"
        }
    }
}

struct ReportSource: Identifiable {
    let num: String
    let title: String
    let url: String
    let domain: String
    var id: String { url + num }
}

// MARK: - Parser

/// Parses the server's self-contained research report HTML into a native model.
/// Tailored to the report template (`main.content` → h2/h3/p/figure/table, a
/// `.sources-panel`, a `.stats-bar`) rather than being a general HTML parser.
enum ReportParser {
    static func parse(_ rawHTML: String) -> ResearchReport {
        // Bound the work: a real report is ~80 KB. Cap hostile/oversized server HTML so the
        // single-pass scanners can't be driven into a multi-second hang on the render path.
        let html = rawHTML.count > 600_000 ? String(rawHTML.prefix(600_000)) : rawHTML
        // Slice the big regions with plain (literal) search — fast, no regex
        // backtracking over the full ~80 KB document.
        let head = slice(html, after: "<main class=\"content\">", before: "</main>") ?? html
        let statsBar = slice(html, after: "<div class=\"stats-bar\">", before: "</div>\n</div>")
            ?? slice(html, after: "<div class=\"stats-bar\">", before: "</section>") ?? ""
        let sourcesHTML = slice(html, after: "<div class=\"sources-panel\">", before: "</details>") ?? ""

        let title = firstMatch(#"<h1[^>]*>(.*?)</h1>"#, in: html).map(clean) ?? "Relatório"
        let stats = parseStats(statsBar)
        let blocks = parseBlocks(head)
        let sources = parseSources(sourcesHTML)
        return ResearchReport(title: title, subtitle: nil, stats: stats, blocks: blocks, sources: sources)
    }

    // MARK: blocks (in document order)

    /// Linear single-pass scanner over the content. Recognizes the report's
    /// block tags in document order — avoids regex backtracking on large input.
    private static func parseBlocks(_ content: String) -> [ReportBlock] {
        let ns = content as NSString
        let n = ns.length
        let tags = ["h2", "h3", "figure", "table", "p"]
        var blocks: [ReportBlock] = []
        var i = 0
        while i < n {
            let lt = ns.range(of: "<", options: [], range: NSRange(location: i, length: n - i))
            if lt.location == NSNotFound { break }
            var advanced = false
            for tag in tags {
                let open = "<\(tag)"
                let probeLen = min(open.count + 1, n - lt.location)
                let probe = ns.substring(with: NSRange(location: lt.location, length: probeLen))
                guard probe.hasPrefix(open) else { continue }
                // The char after "<tag" must end the tag name (space, >, / or newline).
                let after = probe.count > open.count ? probe.last! : ">"
                guard after == ">" || after == " " || after == "/" || after == "\n" || after == "\t" else { continue }
                // End of the opening tag.
                let gt = ns.range(of: ">", options: [], range: NSRange(location: lt.location, length: n - lt.location))
                guard gt.location != NSNotFound else { i = lt.location + 1; advanced = true; break }
                let openTag = ns.substring(with: NSRange(location: lt.location, length: gt.location + 1 - lt.location))
                let bodyStart = gt.location + 1
                let close = "</\(tag)>"
                let closeR = ns.range(of: close, options: [], range: NSRange(location: bodyStart, length: n - bodyStart))
                let innerEnd = closeR.location == NSNotFound ? n : closeR.location
                let inner = ns.substring(with: NSRange(location: bodyStart, length: innerEnd - bodyStart))
                emit(tag: tag, openTag: openTag, inner: inner, into: &blocks)
                i = closeR.location == NSNotFound ? n : closeR.location + close.count
                advanced = true
                break
            }
            if !advanced { i = lt.location + 1 }
        }
        return blocks
    }

    private static func emit(tag: String, openTag: String, inner: String, into blocks: inout [ReportBlock]) {
        switch tag {
        case "h2": add(.heading(level: 2, text: clean(inner)), to: &blocks)
        case "h3": add(.heading(level: 3, text: clean(inner)), to: &blocks)
        case "p":  add(.paragraph(clean(inner)), to: &blocks)
        case "figure":
            if let url = firstMatch(#"data-img-url="([^"]+)""#, in: openTag)
                ?? firstMatch(#"<img[^>]*src="([^"]+)""#, in: inner) {
                blocks.append(.image(url: decode(url)))
            }
        case "table":
            if let t = parseTable(inner) { blocks.append(t) }
        default: break
        }
    }

    private static func add(_ b: ReportBlock, to blocks: inout [ReportBlock]) {
        // Drop empty paragraphs/headings the template emits between sections.
        switch b {
        case .paragraph(let t) where t.isEmpty: return
        case .heading(_, let t) where t.isEmpty: return
        default: blocks.append(b)
        }
    }

    private static func parseTable(_ tbl: String) -> ReportBlock? {
        let headers = allMatches(#"<th\b[^>]*>([\s\S]*?)</th>"#, in: tbl).map(clean)
        var rows: [[String]] = []
        for tr in allMatches(#"<tr\b[^>]*>([\s\S]*?)</tr>"#, in: tbl) {
            let cells = allMatches(#"<td\b[^>]*>([\s\S]*?)</td>"#, in: tr).map(clean)
            if !cells.isEmpty { rows.append(cells) }
        }
        guard !headers.isEmpty || !rows.isEmpty else { return nil }
        return .table(headers: headers, rows: rows)
    }

    private static func parseStats(_ bar: String) -> [(String, String)] {
        guard !bar.isEmpty else { return [] }
        var out: [(String, String)] = []
        for stat in allMatches(#"<div class="stat"[^>]*>([\s\S]*?)</div>"#, in: bar) {
            let spans = allMatches(#"<span[^>]*>([\s\S]*?)</span>"#, in: stat).map(clean).filter { !$0.isEmpty }
            if spans.count >= 2 { out.append((spans[1], spans[0])) }
            else if spans.count == 1 { out.append(("", spans[0])) }
        }
        return out
    }

    private static func parseSources(_ html: String) -> [ReportSource] {
        var out: [ReportSource] = []
        for a in allMatchesFull(#"<a\b[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>"#, in: html) {
            let url = decode(a.0)
            let inner = a.1
            let num = firstMatch(#"<span class="snum">([\s\S]*?)</span>"#, in: inner).map(clean) ?? "\(out.count + 1)"
            let domain = firstMatch(#"<span class="sdomain">([\s\S]*?)</span>"#, in: inner).map(clean)
                ?? (URL(string: url)?.host ?? "")
            // Title = the span that is neither snum nor sdomain.
            let titleSpan = allMatchesFull(#"<span(?: class="([^"]*)")?[^>]*>([\s\S]*?)</span>"#, in: inner)
                .first { ($0.0 != "snum" && $0.0 != "sdomain") }?.1
            let title = clean(titleSpan ?? inner)
            guard !url.isEmpty, url.hasPrefix("http") else { continue }
            out.append(ReportSource(num: num, title: title.isEmpty ? domain : title, url: url, domain: domain))
        }
        return out
    }

    // MARK: html helpers

    /// Strips tags and decodes entities, collapsing whitespace.
    static func clean(_ s: String) -> String {
        let noTags = s.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let decoded = decode(noTags)
        return decoded.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decode(_ s: String) -> String {
        var t = s
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
                   "&#x27;": "'", "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–",
                   "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“",
                   "&rdquo;": "”", "&apos;": "'", "&times;": "×", "&deg;": "°"]
        for (k, v) in map { t = t.replacingOccurrences(of: k, with: v) }
        // numeric entities &#123;
        while let r = t.range(of: #"&#(\d+);"#, options: .regularExpression) {
            let num = t[r].dropFirst(2).dropLast()
            if let code = UInt32(num), let scalar = Unicode.Scalar(code) {
                t.replaceSubrange(r, with: String(scalar))
            } else { break }
        }
        return t
    }

    // MARK: regex utilities

    private static func firstMatch(_ pattern: String, in s: String) -> String? {
        allMatches(pattern, in: s).first
    }

    /// First capture group of every match.
    private static func allMatches(_ pattern: String, in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap {
            let r = $0.range(at: 1); return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    /// First + second capture groups of every match.
    private static func allMatchesFull(_ pattern: String, in s: String) -> [(String, String)] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { match in
            func g(_ i: Int) -> String { let r = match.range(at: i); return r.location == NSNotFound ? "" : ns.substring(with: r) }
            return (g(1), g(2))
        }
    }

    /// Literal (non-regex) slice between two markers — fast on large input.
    private static func slice(_ s: String, after: String, before: String) -> String? {
        guard let sr = s.range(of: after) else { return nil }
        let rest = s[sr.upperBound...]
        guard let er = rest.range(of: before) else { return String(rest) }
        return String(rest[..<er.lowerBound])
    }
}
