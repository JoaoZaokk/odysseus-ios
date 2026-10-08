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
    /// Makes a navigation bar adopt the theme (iOS): a solid themed background +
    /// a matching bar color scheme, so the title/buttons stay legible no matter
    /// the device's system appearance. Fixes "light theme, dark menu, blue
    /// selectors" where a sheet's `List`/nav bar fell back to system styling.
    @ViewBuilder
    func themedNavBar(_ theme: Theme) -> some View {
        #if os(iOS)
        self
            .toolbarBackground(theme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(theme.isDark ? .dark : .light, for: .navigationBar)
        #else
        self
        #endif
    }

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
            .odyNavTitle(title, subtitle: subtitle)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) { leading() }
                ToolbarItemGroup(placement: .topBarTrailing) { trailing() }
            }
        #endif
    }

    /// A screen title drawn in the app's font.
    ///
    /// `.navigationTitle` alone hands the string to UIKit, which draws it in
    /// the system sans no matter which family the user picked — with Mono on,
    /// twelve titles came out in sans next to Mono content. The title is still
    /// set (VoiceOver, the back button of the next screen); the visible one is
    /// a `.principal` item. macOS draws its own header and keeps the plain title.
    ///
    /// `verbatim` is for text that is already final (a conversation's name, a
    /// username, `L(...)` output) and must not be looked up in the catalogue.
    @ViewBuilder
    func odyNavTitle(_ title: String, subtitle: String? = nil, parent: String? = nil, verbatim: Bool = false) -> some View {
        #if os(iOS)
        modifier(OdyNavTitle(title: title, subtitle: subtitle, parent: parent, verbatim: verbatim))
        #else
        if verbatim { navigationTitle(Text(verbatim: title)) } else { navigationTitle(LocalizedStringKey(title)) }
        #endif
    }
}

#if os(iOS)
private struct OdyNavTitle: ViewModifier {
    let title: String
    let subtitle: String?
    /// A screen reached through a differently named row ("Aparência" opens
    /// the theme screen) says where it came from: "Aparência › Tema".
    let parent: String?
    let verbatim: Bool
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .navigationTitle(verbatim ? Text(verbatim: title) : Text(LocalizedStringKey(title)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        HStack(spacing: 6) {
                            if let parent {
                                Text(LocalizedStringKey(parent))
                                    .font(.ody(.subheadline))
                                    .foregroundStyle(theme.accent)
                                Image(systemName: "chevron.right")
                                    .font(.ody(size: 10, weight: .semibold))
                                    .foregroundStyle(theme.secondaryText)
                                    .accessibilityHidden(true)
                            }
                            (verbatim ? Text(verbatim: title) : Text(LocalizedStringKey(title)))
                                .font(.ody(.headline, weight: .semibold))
                                .foregroundStyle(theme.fg)
                                .lineLimit(1)
                        }
                        if let subtitle, !subtitle.isEmpty {
                            Text(verbatim: subtitle)
                                .font(.ody(size: 11))
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
            }
    }
}
#endif

/// A text button for a navigation bar, in the app's font and accent.
///
/// On iOS 26 a toolbar `Button("Fechar")` is drawn by SwiftUI's own glass
/// item, which reads neither `Font.ody` nor the `UIBarButtonItem` appearance
/// proxy: with Mono picked, "Fechar", "Cancelar" and "Salvar" still came out in
/// the system sans. A label with its own font is respected.
struct BarButton: View {
    let title: LocalizedStringKey
    var role: ButtonRole?
    let action: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: LocalizedStringKey, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.ody(size: 15))
                .foregroundStyle(isEnabled ? theme.accent : theme.secondaryText)
        }
    }
}

/// Themed search field rendered in the content, not in the chrome.
///
/// The app's screens use this instead of `.searchable`: on iOS 26 that floats
/// at the bottom edge, in the system sans, away from the list it filters; on
/// macOS it routes through the crashy NSToolbar bridge.
struct OdySearchField: View {
    @Binding var text: String
    let prompt: String
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            field
            #if os(iOS)
            // iOS search fields offer a way out once focused: clear AND leave.
            // (macOS has Esc.)
            if focused {
                Button { text = ""; focused = false } label: {
                    Text("Cancelar").font(.ody(.subheadline)).foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .frame(minHeight: Spacing.tapTarget)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            #endif
        }
        .animation(.easeOut(duration: 0.18), value: focused)
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, 8)
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.secondaryText)
                .font(.ody(size: 12))
            Button("") { focused = true }.keyboardShortcut(OdyShortcuts.search)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
            TextField(LocalizedStringKey(prompt), text: $text)
                .focused($focused)
                .textFieldStyle(.plain)
                .font(.ody(.subheadline))
                .foregroundStyle(theme.fg)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(minHeight: 36)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
}

#if os(macOS)
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
                    Text(LocalizedStringKey(title))
                        .font(.ody(.headline))
                        .foregroundStyle(theme.fg)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(LocalizedStringKey(subtitle))
                            .font(.ody(size: 10))
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
