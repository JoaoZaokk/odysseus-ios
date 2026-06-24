import SwiftUI

@main
struct OdysseusApp: App {
    @StateObject private var app = AppState()
    @StateObject private var themes = ThemeStore()

    init() { FontLoader.registerBundledFonts() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(themes)
                .environment(\.theme, themes.effectiveTheme)
                .preferredColorScheme(themes.theme.isDark ? .dark : .light)
                .tint(themes.theme.accent)
                // Font family is read by the non-View `Font.ody` helper via a
                // global; bump identity so the whole tree re-renders on change.
                .id(themes.fontFamily)
                #if os(macOS)
                // The app draws all its own controls; suppress AppKit's default
                // button/field chrome so they don't get a bordered "square".
                .buttonStyle(.plain)
                .textFieldStyle(.plain)
                .frame(minWidth: 820, minHeight: 560)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var themes: ThemeStore
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            // Transparency backdrop (desktop vibrancy on macOS; frosted on iOS).
            if themes.transparency {
                #if os(macOS)
                VisualEffectBackground().ignoresSafeArea()
                #else
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                #endif
            }
            theme.bg.ignoresSafeArea()   // translucent when transparency is on
            switch app.phase {
            case .launching:
                LaunchView()
            case .login:
                LoginView()
            case .main:
                MainView(app: app)
            }
        }
        .overlay {
            if themes.background != .none {
                AnimatedBackground(pattern: themes.background, tint: theme.accent)
            }
        }
        .task { await app.bootstrap() }
    }
}

struct LaunchView: View {
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(spacing: 20) {
            BrandMark(size: 72)
            ProgressView()
                .tint(theme.accent)
        }
    }
}

/// The little sail/wave glyph used in the favicon, redrawn in SwiftUI.
struct BrandMark: View {
    @Environment(\.theme) private var theme
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                // Sail
                Path { p in
                    p.move(to: CGPoint(x: w * 0.5, y: h * 0.12))
                    p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.68))
                    p.addLine(to: CGPoint(x: w * 0.18, y: h * 0.68))
                    p.closeSubpath()
                }
                .fill(theme.accent)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.5, y: h * 0.25))
                    p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.68))
                    p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.68))
                    p.closeSubpath()
                }
                .fill(theme.accent.opacity(0.6))
                // Wave
                Path { p in
                    p.move(to: CGPoint(x: w * 0.12, y: h * 0.78))
                    p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.82),
                                   control: CGPoint(x: w * 0.31, y: h * 0.70))
                    p.addQuadCurve(to: CGPoint(x: w * 0.88, y: h * 0.78),
                                   control: CGPoint(x: w * 0.69, y: h * 0.92))
                }
                .stroke(theme.accent, style: StrokeStyle(lineWidth: max(2, size * 0.08), lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}
