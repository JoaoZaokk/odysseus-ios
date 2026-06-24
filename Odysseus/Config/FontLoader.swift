import CoreText
import Foundation

/// Registers bundled custom fonts (Inter → "Anthropic Sans") at launch, so
/// `Font.custom("Inter", …)` resolves. Programmatic registration works the same
/// on iOS and macOS without Info.plist entries; if a file is missing the app
/// just falls back to the system font.
enum FontLoader {
    static func registerBundledFonts() {
        for name in ["Inter"] {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf")
            guard let url else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
