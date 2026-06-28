import SwiftUI
import ObjectiveC

// MARK: - Shipped languages

/// The languages the app ships translations for. **pt-BR is the development/base
/// language** — its strings are the literals in the Swift source, so it has no
/// `.lproj`. The others are loaded from `Resources/<code>.lproj/Localizable.strings`.
///
/// Users bought the app in India and Japan, so beyond pt-BR/English we ship
/// Japanese and the two most-spoken Indian languages, Hindi and Bengali.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case ptBR = "pt-BR"
    case en   = "en"
    case ja   = "ja"
    case hi   = "hi"
    case bn   = "bn"

    var id: String { rawValue }

    /// Endonym — the language's name written in that language (what users recognize).
    var nativeName: String {
        switch self {
        case .ptBR: return "Português (Brasil)"
        case .en:   return "English"
        case .ja:   return "日本語"
        case .hi:   return "हिन्दी"
        case .bn:   return "বাংলা"
        }
    }

    /// Short label in the *current* UI language, for secondary captions.
    var englishName: String {
        switch self {
        case .ptBR: return "Portuguese (Brazil)"
        case .en:   return "English"
        case .ja:   return "Japanese"
        case .hi:   return "Hindi"
        case .bn:   return "Bengali"
        }
    }

    var flag: String {
        switch self {
        case .ptBR: return "🇧🇷"
        case .en:   return "🇺🇸"
        case .ja:   return "🇯🇵"
        case .hi:   return "🇮🇳"
        case .bn:   return "🇧🇩"
        }
    }

    /// `.lproj` folder name in the bundle. pt-BR returns nil (it's the literals).
    var lprojName: String? { self == .ptBR ? nil : rawValue }

    var locale: Locale { Locale(identifier: rawValue) }

    /// Best shipped match for a device/system BCP-47 code (e.g. "ja-JP", "hi", "bn-IN").
    static func match(systemCode code: String) -> AppLanguage? {
        let lower = code.lowercased()
        if lower.hasPrefix("pt") { return .ptBR }
        if lower.hasPrefix("en") { return .en }
        if lower.hasPrefix("ja") { return .ja }
        if lower.hasPrefix("hi") { return .hi }
        if lower.hasPrefix("bn") { return .bn }
        return nil
    }
}

// MARK: - Manager

/// Holds the active app language and persists the user's choice. Supports an
/// **Automatic** mode that follows the phone's native language, and a manual
/// override picked in Ajustes › Idioma. Applying a language swaps `Bundle.main`
/// so every `Text("…")` / `String(localized:)` resolves to it live.
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private let storeKey = "app.language"   // "auto" or an AppLanguage rawValue

    /// True when the app follows the device language automatically (default).
    @Published private(set) var isAutomatic: Bool
    /// The currently resolved, active language.
    @Published private(set) var active: AppLanguage

    private init() {
        let stored = UserDefaults.standard.string(forKey: storeKey)
        if let stored, stored != "auto", let lang = AppLanguage(rawValue: stored) {
            isAutomatic = false
            active = lang
        } else {
            // First launch (or "auto") → detect the phone's native language.
            isAutomatic = true
            active = LocalizationManager.detectDeviceLanguage()
        }
        Bundle.setAppLanguage(active)
    }

    /// Detects the phone's native language and maps it to a shipped language.
    /// Falls back to English (the app's lingua franca outside Brazil).
    static func detectDeviceLanguage() -> AppLanguage {
        for code in Locale.preferredLanguages {
            if let lang = AppLanguage.match(systemCode: code) { return lang }
        }
        return .en
    }

    var locale: Locale { active.locale }

    /// What the picker shows selected: `nil` means the Automatic row.
    var selection: AppLanguage? { isAutomatic ? nil : active }

    /// The language the device would resolve to in Automatic mode (for the caption).
    var detected: AppLanguage { LocalizationManager.detectDeviceLanguage() }

    /// Identity string for the root `.id(...)` so the whole tree re-localizes on change.
    var identity: String { isAutomatic ? "auto" : active.rawValue }

    /// Pick a language, or pass `nil` for Automatic (follow the device).
    func use(_ language: AppLanguage?) {
        if let language {
            isAutomatic = false
            active = language
            UserDefaults.standard.set(language.rawValue, forKey: storeKey)
        } else {
            isAutomatic = true
            active = LocalizationManager.detectDeviceLanguage()
            UserDefaults.standard.set("auto", forKey: storeKey)
        }
        Bundle.setAppLanguage(active)
        objectWillChange.send()
    }
}

// MARK: - Runtime language override (Bundle swizzle)

private var kAppLanguageBundle: UInt8 = 0

/// Subclass installed onto `Bundle.main` at runtime so every localized-string
/// lookup is routed to the chosen `.lproj`. When no override bundle is set
/// (pt-BR, or a missing `.lproj`), it falls back to the literal key — which is
/// the Portuguese source string.
final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &kAppLanguageBundle) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// Swaps `Bundle.main`'s class once, then points it at the language's `.lproj`.
    static func setAppLanguage(_ language: AppLanguage) {
        if !(Bundle.main is LocalizedBundle) {
            object_setClass(Bundle.main, LocalizedBundle.self)
        }
        let langBundle: Bundle?
        if let lproj = language.lprojName,
           let path = Bundle.main.path(forResource: lproj, ofType: "lproj") {
            langBundle = Bundle(path: path)
        } else {
            langBundle = nil   // pt-BR / not found → literal (Portuguese) keys
        }
        objc_setAssociatedObject(Bundle.main, &kAppLanguageBundle, langBundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
