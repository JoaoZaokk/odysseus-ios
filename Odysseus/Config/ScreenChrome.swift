import SwiftUI

// Cross-platform screen chrome (title + leading/trailing actions).
//
// On **iOS** this maps to the native `.toolbar` (a single `ToolbarItemGroup` per
// side — never multiple `ToolbarItem`s, which on macOS can crash NSToolbar).
//
// On **macOS** we do NOT use `.toolbar` at all: the AppKit NSToolbar bridge
// crashes intermittently (`-[NSToolbar _insertNewItemWithItemIdentifier:]`) when
// the NavigationSplitView detail swaps toolbars during navigation. Instead each
// screen draws its own themed header bar in-content, which also themes correctly.

extension View {
    @ViewBuilder
    func screenChrome<L: View, T: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: () -> L = { EmptyView() },
        @ViewBuilder trailing: () -> T = { EmptyView() }
    ) -> some View {
        #if os(macOS)
        ScreenChromeContainer(title: title, subtitle: subtitle,
                              leading: leading(), trailing: trailing(), content: self)
        #else
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) { leading() }
                ToolbarItemGroup(placement: .topBarTrailing) { trailing() }
            }
        #endif
    }
}

extension View {
    /// `.searchable` on iOS. On macOS `.searchable` routes through the same crashy
    /// NSToolbar bridge, so we render a themed in-content search field instead.
    @ViewBuilder
    func odySearchable(text: Binding<String>, prompt: String) -> some View {
        #if os(macOS)
        VStack(spacing: 0) {
            MacSearchField(text: text, prompt: prompt)
            self
        }
        #else
        self.searchable(text: text, prompt: prompt)
        #endif
    }
}

#if os(macOS)
struct MacSearchField: View {
    @Binding var text: String
    let prompt: String
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.secondaryText)
                .font(.ody(size: 12))
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.ody(.subheadline, design: .monospaced))
                .foregroundStyle(theme.fg)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct ScreenChromeContainer<L: View, T: View, C: View>: View {
    let title: String
    let subtitle: String?
    let leading: L
    let trailing: T
    let content: C
    @Environment(\.theme) private var theme
    @Environment(\.paneControls) private var pane

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                leading
                // Split-view pane controls (only present when this screen is a
                // column in the workspace): close + expand-to-corner. Kept on the
                // LEADING edge so they stay visible even when a narrow split
                // column's right edge is clipped (and it mirrors the mac's
                // top-left red close button).
                if pane.onClose != nil || pane.onExpand != nil {
                    HStack(spacing: 7) {
                        if let close = pane.onClose {
                            Button(action: close) {
                                Image(systemName: "xmark.circle.fill").font(.ody(size: 14))
                            }
                            .buttonStyle(.plain).foregroundStyle(theme.accent)
                            .help("Fechar painel")
                        }
                        if let expand = pane.onExpand {
                            Button(action: expand) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.ody(size: 11))
                            }
                            .buttonStyle(.plain).foregroundStyle(theme.secondaryText)
                            .help("Expandir / jogar pro canto")
                        }
                    }
                    .padding(.trailing, 2)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.ody(.headline, design: .monospaced))
                        .foregroundStyle(theme.fg)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.ody(size: 10, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 46)
            .background(theme.bg)
            Divider().overlay(theme.border)
            content
        }
    }
}
#endif
