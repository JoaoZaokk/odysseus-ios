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
    case es   = "es"
    case fr   = "fr"
    case it   = "it"
    case de   = "de"
    case deAT = "de-AT"
    case deCH = "de-CH"
    case nl   = "nl"
    case pl   = "pl"
    case cs   = "cs"
    case sk   = "sk"
    case sl   = "sl"
    case hr   = "hr"
    case bg   = "bg"
    case mk   = "mk"
    case sr   = "sr"
    case uk   = "uk"
    case be   = "be"
    case ru   = "ru"
    case tr   = "tr"
    case hu   = "hu"
    case vi   = "vi"
    case ind  = "id"   // Indonesian (case can't be `id` — clashes with Identifiable)
    case ms   = "ms"
    case ja   = "ja"
    case ko   = "ko"
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case zhHK   = "zh-HK"   // Traditional Chinese — Hong Kong (Cantonese conventions)
    case hi   = "hi"
    case bn   = "bn"
    case ar   = "ar"
    case fa   = "fa"
    case ur   = "ur"
    case ps   = "ps"
    case fi   = "fi"
    case sv   = "sv"
    case lv   = "lv"
    case lb   = "lb"
    case th   = "th"
    case he   = "he"
    case ug   = "ug"   // Uyghur — RTL, Arabic script
    case bo   = "bo"   // Tibetan

    var id: String { rawValue }

    /// (endonym shown in the picker, English name for captions, flag).
    private var meta: (native: String, english: String, flag: String) {
        switch self {
        case .ptBR:   return ("Português (Brasil)", "Portuguese (Brazil)", "🇧🇷")
        case .en:     return ("English", "English", "🇺🇸")
        case .es:     return ("Español", "Spanish", "🇪🇸")
        case .fr:     return ("Français", "French", "🇫🇷")
        case .it:     return ("Italiano", "Italian", "🇮🇹")
        case .de:     return ("Deutsch", "German", "🇩🇪")
        case .deAT:   return ("Deutsch (Österreich)", "German (Austria)", "🇦🇹")
        case .deCH:   return ("Deutsch (Schweiz)", "German (Switzerland)", "🇨🇭")
        case .nl:     return ("Nederlands", "Dutch", "🇳🇱")
        case .pl:     return ("Polski", "Polish", "🇵🇱")
        case .cs:     return ("Čeština", "Czech", "🇨🇿")
        case .sk:     return ("Slovenčina", "Slovak", "🇸🇰")
        case .sl:     return ("Slovenščina", "Slovenian", "🇸🇮")
        case .hr:     return ("Hrvatski", "Croatian", "🇭🇷")
        case .bg:     return ("Български", "Bulgarian", "🇧🇬")
        case .mk:     return ("Македонски", "Macedonian", "🇲🇰")
        case .sr:     return ("Српски", "Serbian", "🇷🇸")
        case .uk:     return ("Українська", "Ukrainian", "🇺🇦")
        case .be:     return ("Беларуская", "Belarusian", "🇧🇾")
        case .ru:     return ("Русский", "Russian", "🇷🇺")
        case .tr:     return ("Türkçe", "Turkish", "🇹🇷")
        case .hu:     return ("Magyar", "Hungarian", "🇭🇺")
        case .vi:     return ("Tiếng Việt", "Vietnamese", "🇻🇳")
        case .ind:    return ("Bahasa Indonesia", "Indonesian", "🇮🇩")
        case .ms:     return ("Bahasa Melayu", "Malay", "🇲🇾")
        case .ja:     return ("日本語", "Japanese", "🇯🇵")
        case .ko:     return ("한국어", "Korean", "🇰🇷")
        case .zhHans: return ("简体中文", "Chinese (Simplified)", "🇨🇳")
        case .zhHant: return ("繁體中文", "Chinese (Traditional)", "🇹🇼")
        case .zhHK:   return ("繁體中文（香港）", "Chinese (Hong Kong)", "🇭🇰")
        case .hi:     return ("हिन्दी", "Hindi", "🇮🇳")
        case .bn:     return ("বাংলা", "Bengali", "🇧🇩")
        case .ar:     return ("العربية", "Arabic", "🇸🇦")
        case .fa:     return ("فارسی", "Persian", "🇮🇷")
        case .ur:     return ("اردو", "Urdu", "🇵🇰")
        case .ps:     return ("پښتو", "Pashto", "🇦🇫")
        case .fi:     return ("Suomi", "Finnish", "🇫🇮")
        case .sv:     return ("Svenska", "Swedish", "🇸🇪")
        case .lv:     return ("Latviešu", "Latvian", "🇱🇻")
        case .lb:     return ("Lëtzebuergesch", "Luxembourgish", "🇱🇺")
        case .th:     return ("ไทย", "Thai", "🇹🇭")
        case .he:     return ("עברית", "Hebrew", "🇮🇱")
        case .ug:     return ("ئۇيغۇرچە", "Uyghur", "🇨🇳")
        case .bo:     return ("བོད་སྐད་", "Tibetan", "🇨🇳")
        }
    }

    /// Endonym — the language's name written in that language (what users recognize).
    var nativeName: String { meta.native }
    /// Short label in English, for secondary captions.
    var englishName: String { meta.english }
    var flag: String { meta.flag }

    /// Right-to-left scripts (drive `\.layoutDirection`).
    var isRTL: Bool { self == .ar || self == .fa || self == .ur || self == .ps || self == .he || self == .ug }

    /// `.lproj` folder name in the bundle. pt-BR returns nil (it's the literals).
    /// pt-BR is the base language, but it still ships a `.lproj` (mapping every key
    /// to itself). Without one, SwiftUI resolves `Text()` against the environment
    /// locale, finds no pt-BR table, falls back to `CFBundleDevelopmentRegion` (en)
    /// and shows Brazilians the English translation of their own app.
    var lprojName: String? { rawValue }

    var locale: Locale { Locale(identifier: rawValue) }

    /// Best shipped match for a device/system BCP-47 code (e.g. "ja-JP", "zh-Hant-TW", "de-CH").
    static func match(systemCode code: String) -> AppLanguage? {
        let c = code.lowercased()
        if c.hasPrefix("pt") { return .ptBR }
        if c.hasPrefix("zh") || c.hasPrefix("yue") {
            if c.hasPrefix("yue") || c.contains("-hk") || c.contains("-mo") { return .zhHK }
            if c.contains("hant") || c.contains("-tw") { return .zhHant }
            return .zhHans
        }
        if c.hasPrefix("de") {
            if c.contains("-at") { return .deAT }
            if c.contains("-ch") { return .deCH }
            return .de
        }
        let map: [String: AppLanguage] = [
            "en": .en, "es": .es, "fr": .fr, "it": .it, "nl": .nl, "pl": .pl, "cs": .cs,
            "sk": .sk, "sl": .sl, "hr": .hr, "bg": .bg, "mk": .mk, "sr": .sr,
            "uk": .uk, "be": .be, "ru": .ru, "tr": .tr, "hu": .hu, "vi": .vi,
            "id": .ind, "in": .ind, "ms": .ms, "ja": .ja, "ko": .ko,
            "hi": .hi, "bn": .bn, "ar": .ar, "fa": .fa, "ur": .ur, "ps": .ps,
            "fi": .fi, "sv": .sv, "lv": .lv, "lb": .lb, "th": .th,
            "he": .he, "iw": .he, "ug": .ug, "bo": .bo,
        ]
        return map[String(c.prefix(2))]
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

    /// Layout direction for the active language (RTL for ar/fa/ur/ps).
    var layoutDirection: LayoutDirection { active.isRTL ? .rightToLeft : .leftToRight }

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
