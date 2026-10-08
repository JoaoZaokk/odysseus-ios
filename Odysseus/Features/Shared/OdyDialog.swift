import SwiftUI

// The app's own alert box.
//
// `UIAlertController` cannot be themed: no appearance proxy reaches it, so
// with Mono picked every confirmation still came up in the system sans, on
// the system grey. `.odyAlert` / `.odyConfirmationDialog` take the same
// arguments as `.alert` / `.confirmationDialog` — buttons with roles and text
// fields in `actions`, a `Text` in `message` — and draw a themed box instead.
//
// iOS only. macOS keeps the system alert (it already sheets out of the
// window, and AppKit draws it in the window's style).

extension View {
    // Base forms take a `Text`; the key and string forms below funnel into
    // them, with the same overload rules as SwiftUI's `.alert` (a literal is a
    // catalogue key, a `String` value is shown as is). The `StringProtocol`
    // forms are disfavoured, as SwiftUI's own are: without that a literal
    // binds to the generic `S == String` and skips the catalogue.

    func odyAlert<A: View, M: View>(_ title: Text, isPresented: Binding<Bool>,
                                    @ViewBuilder actions: () -> A,
                                    @ViewBuilder message: () -> M) -> some View {
        modifier(OdyAlertModifier(title: title, isPresented: isPresented,
                                  actions: actions(), message: message()))
    }

    func odyAlert<T, A: View, M: View>(_ title: Text, isPresented: Binding<Bool>,
                                       presenting data: T?,
                                       @ViewBuilder actions: (T) -> A,
                                       @ViewBuilder message: (T) -> M) -> some View {
        modifier(OdyAlertModifier(title: title, isPresented: isPresented,
                                  actions: data.map(actions), message: data.map(message)))
    }

    func odyAlert<A: View, M: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>,
                                    @ViewBuilder actions: () -> A,
                                    @ViewBuilder message: () -> M) -> some View {
        odyAlert(Text(titleKey), isPresented: isPresented, actions: actions, message: message)
    }

    @_disfavoredOverload
    func odyAlert<S: StringProtocol, A: View, M: View>(_ title: S, isPresented: Binding<Bool>,
                                                       @ViewBuilder actions: () -> A,
                                                       @ViewBuilder message: () -> M) -> some View {
        odyAlert(Text(title), isPresented: isPresented, actions: actions, message: message)
    }

    func odyAlert<A: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>,
                           @ViewBuilder actions: () -> A) -> some View {
        odyAlert(Text(titleKey), isPresented: isPresented, actions: actions, message: { EmptyView() })
    }

    @_disfavoredOverload
    func odyAlert<S: StringProtocol, A: View>(_ title: S, isPresented: Binding<Bool>,
                                              @ViewBuilder actions: () -> A) -> some View {
        odyAlert(Text(title), isPresented: isPresented, actions: actions, message: { EmptyView() })
    }

    func odyAlert<T, A: View, M: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>,
                                       presenting data: T?,
                                       @ViewBuilder actions: (T) -> A,
                                       @ViewBuilder message: (T) -> M) -> some View {
        odyAlert(Text(titleKey), isPresented: isPresented, presenting: data, actions: actions, message: message)
    }

    @_disfavoredOverload
    func odyAlert<S: StringProtocol, T, A: View, M: View>(_ title: S, isPresented: Binding<Bool>,
                                                          presenting data: T?,
                                                          @ViewBuilder actions: (T) -> A,
                                                          @ViewBuilder message: (T) -> M) -> some View {
        odyAlert(Text(title), isPresented: isPresented, presenting: data, actions: actions, message: message)
    }

    /// Same box as `odyAlert`: a centred card reads better than an action
    /// sheet for the two or three choices these confirmations carry.
    func odyConfirmationDialog<A: View, M: View>(_ title: Text, isPresented: Binding<Bool>,
                                                 titleVisibility: Visibility = .automatic,
                                                 @ViewBuilder actions: () -> A,
                                                 @ViewBuilder message: () -> M) -> some View {
        odyAlert(title, isPresented: isPresented, actions: actions, message: message)
    }

    func odyConfirmationDialog<A: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>,
                                        titleVisibility: Visibility = .automatic,
                                        @ViewBuilder actions: () -> A) -> some View {
        odyAlert(Text(titleKey), isPresented: isPresented, actions: actions, message: { EmptyView() })
    }
}

private struct OdyAlertModifier<A: View, M: View>: ViewModifier {
    let title: Text
    @Binding var isPresented: Bool
    let actions: A
    let message: M

    #if os(iOS)
    /// Mirrors `isPresented` without the cover's slide-up: the box fades in on
    /// its own, like an alert, instead of riding up from the bottom edge.
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: Binding(get: { shown }, set: { set($0) })) {
                OdyDialog(title: title, actions: actions, message: message) { set(false) }
                    .presentationBackground(.clear)
            }
            .onChange(of: isPresented) { _, now in instant { shown = now } }
            .onAppear { if isPresented { instant { shown = true } } }
    }

    private func set(_ value: Bool) {
        instant { shown = value }
        if isPresented != value { isPresented = value }
    }

    private func instant(_ change: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, change)
    }
    #else
    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented, actions: { actions }, message: { message })
    }
    #endif
}

#if os(iOS)
/// The box itself: dimmed backdrop, a themed card, the title, the message,
/// the fields and the buttons — all in the app's font.
struct OdyDialog<A: View, M: View>: View {
    let title: Text
    let actions: A
    let message: M
    let close: () -> Void
    @Environment(\.theme) private var theme
    @State private var appeared = false
    /// Set on the first tap, so a second tap during the fade-out cannot run
    /// an action twice (a system alert is gone on the first one).
    @State private var closing = false
    /// The title + message block's natural height, so it only scrolls when it
    /// would not fit.
    @State private var headerHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(appeared ? 0.45 : 0)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                card(maxTextHeight: geo.size.height * 0.5)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.18)) { appeared = true } }
    }

    private func card(maxTextHeight: CGFloat) -> some View {
        VStack(spacing: 16) {
            // A long message (a recovered transcription, an error) scrolls
            // inside the card; the buttons below it always stay on screen.
            ScrollView {
                header.background(GeometryReader { g in
                    Color.clear.preference(key: DialogHeaderHeight.self, value: g.size.height)
                })
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(headerHeight, maxTextHeight))
            .onPreferenceChange(DialogHeaderHeight.self) { headerHeight = $0 }

            VStack(spacing: 8) {
                actions
            }
            .buttonStyle(OdyDialogButtonStyle(theme: theme, close: dismiss))
            .textFieldStyle(OdyDialogFieldStyle(theme: theme))
            .allowsHitTesting(!closing)
        }
        .padding(Spacing.gutter)
        .frame(maxWidth: 320)
        // Opaque under the panel colour: with Transparência on the panel is
        // see-through, and the screen behind bled into the confirmation.
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
        .padding(.horizontal, Spacing.gutter)
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        VStack(spacing: 6) {
            title
                .font(.ody(.headline, weight: .semibold))
                .foregroundStyle(theme.fg)
                .accessibilityAddTraits(.isHeader)
            message
                .font(.ody(.footnote))
                .foregroundStyle(theme.secondaryText)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    /// Fade out, then take the cover down. Every button closes the box, as a
    /// system alert's buttons do.
    private func dismiss() {
        closing = true
        withAnimation(.easeIn(duration: 0.14)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { close() }
    }
}

private struct DialogHeaderHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Full-width buttons, coloured by role: destructive in the danger colour,
/// cancel quiet, anything else the accent. Runs the caller's action, then
/// closes the box.
private struct OdyDialogButtonStyle: PrimitiveButtonStyle {
    let theme: Theme
    let close: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        let role = configuration.role
        Button {
            configuration.trigger()
            close()
        } label: {
            configuration.label
                .font(.ody(.subheadline, weight: role == .cancel ? .regular : .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: Spacing.tapTarget)
                .foregroundStyle(foreground(role))
                .background(background(role), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(role == .cancel ? theme.border : .clear, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func foreground(_ role: ButtonRole?) -> Color {
        switch role {
        case .destructive?: return .white
        case .cancel?: return theme.fg
        default: return .white
        }
    }

    private func background(_ role: ButtonRole?) -> Color {
        switch role {
        case .destructive?: return theme.danger
        case .cancel?: return .clear
        default: return theme.accent
        }
    }
}

/// A text field inside the box: the app's input look.
private struct OdyDialogFieldStyle: TextFieldStyle {
    let theme: Theme

    // swiftlint:disable:next identifier_name
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.ody(.body))
            .foregroundStyle(theme.fg)
            .padding(.horizontal, 12)
            .frame(minHeight: Spacing.tapTarget)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(theme.border, lineWidth: 1))
    }
}
#endif
