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

    /// `.lproj` folder name in the bundle — the raw value, for every language.
    ///
    /// Non-optional on purpose. It was `String?` from a time when pt-BR was the
    /// literals and shipped no catalogue; it ships one now (mapping every key to
    /// itself), because without it SwiftUI resolves `Text()` against the
    /// environment locale, finds no pt-BR table, falls back to
    /// `CFBundleDevelopmentRegion` (en) and shows Brazilians the English
    /// translation of their own app. The optionality outlived its one nil case
    /// and left four call sites guarding against something that cannot happen.
    var lprojName: String { rawValue }

    var locale: Locale { Locale(identifier: rawValue) }

    /// BCP-47 tag for the speech APIs (`AVSpeechSynthesisVoice`,
    /// `SFSpeechRecognizer`). Script subtags like `zh-Hans` are not speech
    /// locales, so the Chinese variants map to their spoken regions; every
    /// other language keeps the bare code and is resolved by prefix match.
    var speechCode: String {
        switch self {
        case .zhHans: return "zh-CN"
        case .zhHant: return "zh-TW"
        case .zhHK:   return "zh-HK"
        default:      return rawValue
        }
    }

    /// ISO-639-1 code, which is what transcription APIs take (OpenAI's
    /// `/audio/transcriptions` documents exactly that). Region and script
    /// subtags are dropped: `pt-BR` → `pt`, `zh-Hans` → `zh`, `de-AT` → `de`.
    var iso639: String { String(rawValue.prefix(while: { $0 != "-" })) }

    /// The code to send to a Whisper-family transcription server, or nil when
    /// the model has never heard of the language and auto-detect is the only
    /// honest option.
    ///
    /// Uyghur is the single gap across the app's 44: it is absent from Whisper's
    /// `LANGUAGES` table, which every server in this family validates against,
    /// so naming it does not degrade to a guess — faster-whisper raises and the
    /// recording is lost. Sending nothing leaves the server detecting, which is
    /// what a Uyghur speaker got before any of this and is still better than an
    /// error. The on-device engine answers the same question separately, in
    /// `VoiceInputManager.chosenWhisperLanguage()`, because SwiftWhisper takes a
    /// `WhisperLanguage` case rather than a code — and spells Hebrew `iw` where
    /// servers spell it `he`.
    var sttServerCode: String? { self == .ug ? nil : iso639 }

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
        // Every remaining language's raw value IS its two-letter code, so the
        // enum answers this. The 39-entry table that used to sit here restated
        // exactly that plus the two legacy codes below — and the six raw values
        // that are not two letters (pt-BR, de-AT, de-CH and the three Chinese)
        // are all resolved by the prefix branches above.
        let two = String(c.prefix(2))
        // Codes some systems still emit for Indonesian and Hebrew.
        if two == "in" { return .ind }
        if two == "iw" { return .he }
        return AppLanguage(rawValue: two)
    }
}

// MARK: - Manager

/// Holds the active app language and persists the user's choice. Supports an
/// **Automatic** mode that follows the phone's native language, and a manual
/// override picked in Ajustes › Idioma. Applying a language swaps `Bundle.main`
/// so every `Text("…")` — and every `L("…")` — resolves to it live.
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
/// Localizes a key at call time, for the strings SwiftUI can't look up itself
/// (plain `String` properties, system dialog text, markdown built by hand).
///
/// Use this and **not** `String(localized:)`: Foundation resolves that one
/// against `Locale.current` through a path that never reaches the override
/// below, so it returned the Portuguese key whenever the app language differed
/// from the device's. This goes through `Bundle.main.localizedString`, which
/// is exactly the method `LocalizedBundle` overrides — the same path
/// `Text("…")` takes. A key with no entry falls back to itself, i.e. the
/// Portuguese source string.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    return args.isEmpty ? format : String(format: format, arguments: args)
}

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
        // nil when the folder is missing → the swizzle falls through to
        // `super`, i.e. the literal (Portuguese) keys.
        let langBundle = Bundle.main.path(forResource: language.lprojName, ofType: "lproj")
            .flatMap(Bundle.init(path:))
        objc_setAssociatedObject(Bundle.main, &kAppLanguageBundle, langBundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

// MARK: - Speech recognition language

/// Which language the transcriber is told to expect.
///
/// Recognition used to be welded to the app's UI language. That is right for
/// most people most of the time and wrong the moment someone is bilingual: a
/// German who wants to dictate one English sentence had to switch the whole app
/// to English and back, and a Cantonese speaker running the app in zh-Hant got
/// pinned to Mandarin. So the bind stays the default and is now one picker away
/// from an explicit choice.
enum SpeechLanguage {
    static let key = "voice.stt.language"
    /// Stored value meaning "whatever Ajustes › Idioma says".
    static let followApp = ""
    /// Stored value meaning "let the engine guess".
    static let auto = "auto"

    static var stored: String { UserDefaults.standard.string(forKey: key) ?? followApp }

    /// The language to pin, or nil when the engine should detect it itself.
    ///
    /// An unrecognised stored code (a language dropped by a later build) falls
    /// back to the app's language rather than to detection — detection is the
    /// worse of the two failure modes, since Whisper-family models guess a
    /// random language on short or noisy audio and hand back nothing.
    @MainActor static func pinned() -> AppLanguage? {
        switch stored {
        case auto:      return nil
        case followApp: return LocalizationManager.shared.active
        case let raw:   return AppLanguage(rawValue: raw) ?? LocalizationManager.shared.active
        }
    }
}
