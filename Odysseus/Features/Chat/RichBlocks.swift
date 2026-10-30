import SwiftUI
import WebKit
import MarkdownUI

/// Code blocks the web draws instead of printing: Mermaid diagrams and charts,
/// SVG, and HTML (behind a preview button, like the web's artifacts). Drawn in
/// a small web view; Mermaid is bundled (`Web/mermaid.min.js`), so nothing is
/// fetched from the internet. Ported from the Open WebUI app 1.12.
enum RichBlock: Equatable {
    case mermaid, svg, html

    init?(language: String?) {
        switch language?.lowercased().trimmingCharacters(in: .whitespaces) {
        case "mermaid": self = .mermaid
        case "svg", "image/svg+xml": self = .svg
        case "html", "htm": self = .html
        default: return nil
        }
    }

    /// Page for a diagram or a picture, in the theme's colours. Reports its
    /// height (and a Mermaid parse failure) back to the app.
    static func page(_ kind: RichBlock, code: String, theme: Theme) -> String {
        let fg = theme.isDark ? "#ececec" : "#1f1f1f"
        let body: String
        // A diagram or a picture never needs the network: nothing leaves the
        // device even if the code asks for it.
        let csp = kind == .html ? "" : """
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src file: 'unsafe-inline'; \
        style-src 'unsafe-inline'; img-src data:; font-src data:">
        """
        switch kind {
        case .mermaid:
            body = """
            <pre class="mermaid">\(escape(code))</pre>
            <script src="mermaid.min.js"></script>
            <script>
            mermaid.initialize({ startOnLoad: false, theme: 'base',
              securityLevel: 'strict', fontFamily: '-apple-system, sans-serif',
              themeVariables: \(chartVariables(theme)) });
            mermaid.run({ querySelector: '.mermaid' })
              .then(report)
              .catch(function () { window.webkit.messageHandlers.size.postMessage(-1); });
            </script>
            """
        case .svg:
            body = code + "<script>report()</script>"
        case .html:
            body = code
        }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        \(csp)
        <style>
        html,body{margin:0;padding:0;background:transparent;color:\(fg);font-family:-apple-system,sans-serif}
        body{display:flex;justify-content:center;padding:8px 4px}
        svg{max-width:100%;height:auto}
        pre.mermaid{margin:0;width:100%;display:flex;justify-content:center}
        </style>
        <script>function report(){window.webkit.messageHandlers.size.postMessage(document.body.scrollHeight)}</script>
        </head><body>\(body)</body></html>
        """
    }

    /// Chart colours from the theme: the accent first, then hues spread around
    /// it — brighter on a dark background, deeper on a light one, so slices
    /// read against both. Mermaid's own dark palette was wine, brown and
    /// near-black on our dark themes. Text and axes take the theme's text
    /// colour; slice outlines take the background.
    static func palette(for theme: Theme) -> [String] {
        let dark = theme.isDark
        let rest = dark
            ? ["2ec4b6", "ffb547", "ff6b6b", "a78bfa", "4ade80", "f472b6", "38bdf8", "facc15"]
            : ["0f8b7f", "c27a0e", "d6453d", "7c5cd6", "1f9a4b", "c43a86", "1f7fbf", "a8860b"]
        let accent = theme.hex.accent.lowercased()
        // Drop an entry whose hue sits next to the accent's, so no two slices
        // look alike. Hue, not brightness: orange and violet can be equally
        // bright and still never be confused.
        let others = rest.filter { hueDistance($0, accent) > 25 }
        return ([accent] + others).prefix(9).map { "#" + $0 }
    }

    /// Degrees between two colours' hues (0–180). A grey has no hue to clash.
    static func hueDistance(_ a: String, _ b: String) -> Double {
        guard let ha = hue(a), let hb = hue(b) else { return 180 }
        let d = abs(ha - hb).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    private static func hue(_ hex: String) -> Double? {
        guard hex.count == 6, let v = Int(hex, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xff) / 255, g = Double((v >> 8) & 0xff) / 255, b = Double(v & 0xff) / 255
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        guard d > 0.08 else { return nil }
        var h: Double
        if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h *= 60
        return h < 0 ? h + 360 : h
    }

    static func chartVariables(_ theme: Theme) -> String {
        let p = palette(for: theme)
        let fg = "#" + theme.hex.fg, bg = "#" + theme.hex.bg, panel = "#" + theme.hex.panel
        var v: [String: String] = [
            // Drawn on a panel-coloured card (the reply has no bubble): shapes
            // take the page background, outlines the card.
            "background": "transparent", "primaryColor": bg, "primaryTextColor": fg,
            "primaryBorderColor": p[0], "lineColor": fg, "textColor": fg, "titleColor": fg,
            "secondaryColor": p[1], "tertiaryColor": bg, "mainBkg": bg, "nodeBorder": p[0],
            "pieTitleTextColor": fg, "pieLegendTextColor": fg, "pieStrokeColor": panel,
            "pieOuterStrokeColor": panel, "pieSectionTextColor": theme.isDark ? "#111111" : "#ffffff",
            "pieOpacity": "1",
            // Edge labels sat white on the second palette colour (teal), unreadable.
            "edgeLabelBackground": bg,
        ]
        for (i, c) in p.enumerated() { v["pie\(i + 1)"] = c }
        let xy = "{\"plotColorPalette\":\"\(p.joined(separator: ","))\",\"titleColor\":\"\(fg)\","
            + "\"xAxisLabelColor\":\"\(fg)\",\"yAxisLabelColor\":\"\(fg)\",\"xAxisTitleColor\":\"\(fg)\","
            + "\"yAxisTitleColor\":\"\(fg)\",\"xAxisLineColor\":\"\(fg)\",\"yAxisLineColor\":\"\(fg)\","
            + "\"xAxisTickColor\":\"\(fg)\",\"yAxisTickColor\":\"\(fg)\",\"backgroundColor\":\"transparent\"}"
        let pairs = v.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\"\($0.value)\"" }
        return "{" + pairs.joined(separator: ",") + ",\"xyChart\":" + xy + "}"
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// The HTML preview: a page as a browser shows it. A fragment (no `<html>`)
    /// gets a phone viewport and a plain readable body; it used to open as tiny
    /// black serif text on the sheet's dark background.
    static func preview(_ html: String) -> String {
        if html.range(of: "<html", options: .caseInsensitive) != nil { return html }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{margin:0;padding:16px;font-family:-apple-system,sans-serif;line-height:1.5}</style>
        </head><body>\(html)</body></html>
        """
    }

    /// Where `mermaid.min.js` sits in the bundle; pages load relative to it.
    static var resourceBase: URL? {
        Bundle.main.url(forResource: "mermaid.min", withExtension: "js")?.deletingLastPathComponent()
    }
}

/// A diagram or picture drawn from a code block, sized to its content. If
/// Mermaid cannot parse the code, the plain code block shows instead.
struct RichBlockView<Fallback: View>: View {
    let kind: RichBlock
    let code: String
    @ViewBuilder let fallback: () -> Fallback
    @Environment(\.theme) private var theme
    @State private var height: CGFloat = 180
    @State private var failed = false
    /// The code last drawn. While a reply streams the block grows a token at a
    /// time, half a diagram is no diagram, and a page per token would thrash:
    /// the code shows until it has held still for a moment.
    @State private var settled: String?

    @Environment(\.richBlockResized) private var resized

    var body: some View {
        Group {
            if failed || settled != code {
                fallback()
            } else {
                drawn
            }
        }
        .onChange(of: height) { _, _ in resized() }
        .onChange(of: failed) { _, _ in resized() }
        .task(id: code) {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            failed = false
            settled = code
        }
    }

    private var drawn: some View {
        WebSnippet(html: RichBlock.page(kind, code: code, theme: theme), height: $height, failed: $failed)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border.opacity(0.35), lineWidth: 1))
                .accessibilityIdentifier(kind == .mermaid ? "message.mermaid" : "message.svg")
    }
}

/// An HTML block: its code, and a button that opens it as a page.
struct HTMLBlockView<Code: View>: View {
    let html: String
    @ViewBuilder let code: () -> Code
    @Environment(\.theme) private var theme
    @State private var previewing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            code()
            Button { previewing = true } label: {
                Label("Visualizar", systemImage: "play.rectangle")
                    .font(.ody(size: 13, weight: .semibold))
                    .foregroundStyle(theme.fg)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .frame(minHeight: Spacing.tapTarget)
                    .background(theme.panel, in: Capsule())
                    .overlay(Capsule().stroke(theme.accent.opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("message.htmlPreview")
        }
        .sheet(isPresented: $previewing) {
            NavigationStack {
                WebSnippet(html: RichBlock.preview(html), height: .constant(0), failed: .constant(false), scrolls: true)
                    .ignoresSafeArea(edges: .bottom)
                    .odyNavTitle("Visualizar")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { BarButton("Concluído") { previewing = false } }
                    }
            }
        }
    }
}

/// A WKWebView that renders one page, never navigates away from it, and
/// reports its content height.
struct WebSnippet {
    let html: String
    @Binding var height: CGFloat
    @Binding var failed: Bool
    var scrolls = false

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: WebSnippet
        var loaded: String?
        init(_ parent: WebSnippet) { self.parent = parent }

        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let n = message.body as? Double ?? (message.body as? Int).map(Double.init) else { return }
            DispatchQueue.main.async {
                if n < 0 { self.parent.failed = true } else { self.parent.height = max(40, min(CGFloat(n) + 4, 900)) }
            }
        }

        // The first load is the page itself; links open nowhere from here.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.navigationType == .other ? .allow : .cancel)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    fileprivate func makeWebView(_ context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "size")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        // A drawn block sits on the reply; a previewed page is a page, white
        // unless it paints its own background.
        #if os(iOS)
        view.isOpaque = scrolls
        view.backgroundColor = scrolls ? .white : .clear
        view.scrollView.backgroundColor = scrolls ? .white : .clear
        view.scrollView.isScrollEnabled = scrolls
        #else
        view.setValue(scrolls, forKey: "drawsBackground")
        #endif
        return view
    }

    fileprivate func load(_ view: WKWebView, _ context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.loaded != html else { return }
        context.coordinator.loaded = html
        view.loadHTMLString(html, baseURL: RichBlock.resourceBase)
    }
}

#if os(iOS)
extension WebSnippet: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context) }
    func updateUIView(_ view: WKWebView, context: Context) { load(view, context) }
}
#else
extension WebSnippet: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context) }
    func updateNSView(_ view: WKWebView, context: Context) { load(view, context) }
}
#endif

/// A fenced code block in a reply. Mermaid, SVG and HTML are drawn the way the
/// web draws them; anything else (and a diagram that fails to parse) is the
/// code itself, scrolling sideways, with its language and a copy button.
struct CodeBlockView: View {
    let configuration: CodeBlockConfiguration
    @Environment(\.theme) private var theme
    @State private var copied = false

    var body: some View {
        switch RichBlock(language: configuration.language) {
        case .mermaid?, .svg?:
            RichBlockView(kind: RichBlock(language: configuration.language)!, code: configuration.content) { codeCard }
        case .html?:
            HTMLBlockView(html: configuration.content) { codeCard }
        case nil:
            codeCard
        }
    }

    /// The language and the copy button sit in a row above the code: laid over
    /// it, they covered a long first line.
    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                if let lang = configuration.language, !lang.isEmpty {
                    Text(verbatim: lang)
                        .font(.ody(size: 10))
                        .foregroundStyle(theme.secondaryText)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(theme.bg, in: Capsule())
                }
                Spacer(minLength: 0)
                Button {
                    Clipboard.copy(configuration.content)
                    copied = true
                    Task { try? await Task.sleep(nanoseconds: 1_200_000_000); copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.ody(size: 11))
                        .foregroundStyle(copied ? theme.accent : theme.secondaryText)
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Copiar"))
            }
            .padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .padding(.top, configuration.language?.isEmpty == false ? 0 : 4)
            }
        }
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border.opacity(0.35), lineWidth: 1))
        .markdownMargin(top: 0, bottom: 16)
    }
}

/// Called when a drawn block changes height, so the transcript can stay at its
/// end while the diagrams near it finish drawing (ChatScreen).
private struct RichBlockResizedKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var richBlockResized: () -> Void {
        get { self[RichBlockResizedKey.self] }
        set { self[RichBlockResizedKey.self] = newValue }
    }
}
