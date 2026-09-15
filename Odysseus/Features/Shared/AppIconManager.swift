#if os(iOS)
import UIKit
#endif

/// A home-screen icon. Picked by hand in Ajustes › Aparência — deliberately not
/// tied to the theme: there are 17 themes and 7 icons, so a theme-driven mapping
/// would leave most of the icons unreachable.
enum AppIcon: String, CaseIterable, Identifiable {
    case odysseus, claude, openai, gemini, openwebui, hermesteal, hermesnoir

    var id: String { rawValue }

    /// The name iOS knows it by, or nil for the primary asset-catalog icon.
    /// Every non-nil name is declared in `CFBundleAlternateIcons` (project.yml)
    /// and backed by `Odysseus/AltIcons/AppIcon-<name>@{2x,3x,2x~ipad}.png` —
    /// `setAlternateIconName` refuses a name that is not in both places.
    var alternateName: String? { self == .odysseus ? nil : "AppIcon-\(rawValue)" }

    var label: String {
        switch self {
        case .odysseus:   return "Odysseus"
        case .claude:     return "Claude"
        case .openai:     return "OpenAI"
        case .gemini:     return "Gemini"
        case .openwebui:  return "Open WebUI"
        case .hermesteal: return "Hermes"
        case .hermesnoir: return "Hermes Noir"
        }
    }

    /// Bundled file the picker previews. The icons are loose resources rather
    /// than asset-catalog images (that is what alternate icons require), so they
    /// load by name; the primary sail is in the catalog and unreachable that
    /// way, so `AppIcon-odysseus@3x.png` is bundled for the preview alone.
    var previewImageName: String { self == .odysseus ? "AppIcon-odysseus" : "AppIcon-\(rawValue)" }
}

/// Owns the home-screen icon: the saved choice, and putting it into effect.
/// iOS shows a system alert on every real change (unavoidable) — it lands right
/// after the user taps an icon, which is a deliberate action.
enum AppIconManager {
    static let storageKey = "odysseus.appicon"

    static var selected: AppIcon {
        AppIcon(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .odysseus
    }

    @MainActor
    static func select(_ icon: AppIcon) {
        UserDefaults.standard.set(icon.rawValue, forKey: storageKey)
        apply(icon)
    }

    /// Reconciles the home-screen icon with the saved choice — an install or an
    /// update resets it to the primary one.
    @MainActor
    static func applySaved() { apply(selected) }

    @MainActor
    private static func apply(_ icon: AppIcon) {
        #if os(iOS)
        let app = UIApplication.shared
        // Comparing first keeps the system alert out of every launch.
        guard app.supportsAlternateIcons, app.alternateIconName != icon.alternateName else { return }
        app.setAlternateIconName(icon.alternateName)
        #endif
    }
}
