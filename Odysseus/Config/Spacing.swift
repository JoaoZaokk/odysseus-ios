import SwiftUI

/// Layout measures for the whole app, in one place. Before this each view wrote
/// its own number and the content margin wandered between 0 and 27 from one
/// screen to the next.
///
/// Card padding and pill padding are not here on purpose: they are a
/// component's inside, not the screen's grid.
enum Spacing {
    /// The one side margin for content.
    static let gutter: CGFloat = 20

    /// Leading column for a row's icon or marker.
    static let leadingColumn: CGFloat = 24
    /// Gap between that column and the row's text.
    static let iconGap: CGFloat = 12

    /// Where a row's text starts, measured from the row's content edge (the
    /// row insets — `gutterRowInsets` — already put that edge on the gutter).
    /// The separator starts here too: 20 + 24 + 12 = 56 on screen.
    static let separatorInset: CGFloat = leadingColumn + iconGap
    /// Separator inset for a row without an icon column: the content edge.
    static let separatorInsetPlain: CGFloat = 0

    /// Room after the last row of a list, ABOVE the safe area the system adds.
    static let bottomBreathing: CGFloat = 16
    /// Distance from a lone block (empty state, voice mic) to the content above.
    /// It sits under that content; it does not float in the middle of the void.
    static let voidOffset: CGFloat = 64
    /// Smallest tappable target.
    static let tapTarget: CGFloat = 44

    /// Reading column on a wide screen (iPad, Mac): the chat's messages and a
    /// list's rows stop at this width, centred.
    static let readableWidth: CGFloat = 720

    /// How wide a screen's content may grow: the reading column on a regular
    /// width (iPad), unlimited on compact (iPhone, iPad slide-over).
    static func readableMaxWidth(regular: Bool) -> CGFloat {
        regular ? readableWidth : .infinity
    }
}

#if os(iOS)
/// Centres a screen's content (a list, and the search field or quick-add
/// bar above it) in the reading column on iPad. The view itself narrows: a
/// `List` ignored a leading content margin on iPad (35 pt on the left, 188
/// on the right), so the column is a frame, the same as the chat's.
private struct ReadableColumn: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: Spacing.readableMaxWidth(regular: sizeClass == .regular))
            .frame(maxWidth: .infinity)
    }
}
#endif

extension View {
    /// See `ReadableColumn`. iPhone is untouched; macOS keeps its panes as
    /// they are.
    @ViewBuilder func readableColumn() -> some View {
        #if os(iOS)
        modifier(ReadableColumn())
        #else
        self
        #endif
    }
}

extension View {
    /// Pins a `List` row's separator to a fixed leading inset.
    ///
    /// Without it SwiftUI anchors the hairline on the first text it finds in
    /// the row, so a calendar event with a location ("Meet") got its separator
    /// under the location while the next event got it under the title.
    func rowSeparatorInset(_ inset: CGFloat = Spacing.separatorInset) -> some View {
        alignmentGuide(.listRowSeparatorLeading) { _ in inset }
    }

    /// Room under a list's last row, above the safe area: without it the last
    /// row sat flush on the bottom edge (or behind the Espaços bar).
    func listBottomBreathing() -> some View {
        contentMargins(.bottom, Spacing.bottomBreathing, for: .scrollContent)
    }

    /// Standard row insets on the app's gutter. Pair with `rowSeparatorInset`.
    func gutterRowInsets(vertical: CGFloat = 6) -> some View {
        listRowInsets(EdgeInsets(top: vertical, leading: Spacing.gutter,
                                 bottom: vertical, trailing: Spacing.gutter))
    }
}

extension View {
    /// Separators only BETWEEN rows. A plain `List` also draws one above the
    /// first row and below the last; iOS lists do not, and the stray hairlines
    /// read as a broken edge (Email, Tasks, Library at the top; Brain,
    /// Calendário, Cookbook, Espaços at the bottom).
    /// `between` is what the inner edges get — `.visible` where a list style
    /// would otherwise skip some (the sidebar).
    func edgeSeparators(first: Bool, last: Bool, between: Visibility = .automatic) -> some View {
        self
            .listRowSeparator(first ? .hidden : between, edges: .top)
            .listRowSeparator(last ? .hidden : between, edges: .bottom)
    }
}

/// Fades the trailing edge of a horizontal strip, so a chip cut by the screen
/// edge reads as "more this way" instead of as a layout bug. Mirrored for
/// right-to-left languages: `UnitPoint.leading` is x = 0 in every language.
private struct TrailingFade: ViewModifier {
    @Environment(\.layoutDirection) private var direction

    func body(content: Content) -> some View {
        let rtl = direction == .rightToLeft
        content.mask(
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .black, location: 0.86),
                                   .init(color: .clear, location: 1)],
                           startPoint: rtl ? .trailing : .leading,
                           endPoint: rtl ? .leading : .trailing)
        )
    }
}

extension View {
    func trailingFade() -> some View { modifier(TrailingFade()) }
}

#if os(iOS)
/// A safe area at a side of the window: the system rail on the iPhone Duo's
/// outer display (84 pt, trailing), or any iPhone turned sideways. Toolbar
/// items land in that rail on the Duo, so a screen with one can move controls
/// out of its content and into the bar. Phone only: on iPadOS 26 the floating
/// sidebar is a leading safe area of the detail column, not a rail.
enum SideRail {
    static func present(_ insets: EdgeInsets, idiom: UIUserInterfaceIdiom) -> Bool {
        idiom == .phone && (insets.leading > 0 || insets.trailing > 0)
    }
}

extension View {
    /// Keeps `hasRail` in step with `SideRail.present` for the whole window.
    /// The reader ignores the safe area so its insets are the window's, not
    /// zero from sitting inside them; it follows the Duo opening and closing.
    func readSideRail(_ hasRail: Binding<Bool>) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { hasRail.wrappedValue = SideRail.present(proxy.safeAreaInsets, idiom: UIDevice.current.userInterfaceIdiom) }
                    .onChange(of: proxy.safeAreaInsets) { _, insets in
                        hasRail.wrappedValue = SideRail.present(insets, idiom: UIDevice.current.userInterfaceIdiom)
                    }
            }
            .ignoresSafeArea()
        }
    }
}
#endif
