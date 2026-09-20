import XCTest
@testable import Odysseus

/// Strings added after a release are the ones that leak Portuguese: the app
/// looks up a pt-BR literal as the key, and a key with no entry comes back *as
/// the key*, so a missing translation is invisible — the screen renders, in the
/// wrong language. These pin the copy 1.12 introduced (the home-screen icon
/// picker, the Espaços bar, the foldable voice catalogue) plus one older gap the
/// sweep that found them turned up.
final class NewStringsLocalizedTests: XCTestCase {

    /// The literal as it appears in Swift — which is the catalogue key.
    private let keys = [
        "Ícone",                              // ThemePickerView, icon section
        "Mais",                               // SessionListView, Espaços overflow
        "Aberto", "Fechado",                  // VoiceSettingsView, section state
        "%lld modelos, %lld baixados",        // VoiceSettingsView, section hint
        "Não consegui carregar o modelo %@.", // OnDeviceSTT failure
    ]

    func testEveryNewStringHasAnEntryInEveryCatalogue() throws {
        let appBundle = Bundle(for: LocalizationManager.self)
        for lang in AppLanguage.allCases {
            let lproj = lang.lprojName
            guard let path = appBundle.path(forResource: lproj, ofType: "lproj"),
                  let catalogue = Bundle(path: path) else {
                XCTFail("\(lang.rawValue): no catalogue to check"); continue
            }
            for key in keys {
                let hit = catalogue.localizedString(forKey: key, value: "\u{0}MISS", table: nil)
                XCTAssertNotEqual(hit, "\u{0}MISS", "\(lproj) has no entry for \(key)")
            }
        }
    }

    /// A translation that drops a placeholder crashes `String(format:)` or
    /// prints garbage, and only in that one language — so count them here
    /// instead of on a Korean phone.
    func testPlaceholdersSurviveTranslation() throws {
        let appBundle = Bundle(for: LocalizationManager.self)
        let expected = ["%lld modelos, %lld baixados": ("%lld", 2),
                        "Não consegui carregar o modelo %@.": ("%@", 1)]
        for lang in AppLanguage.allCases {
            guard let path = appBundle.path(forResource: lang.lprojName, ofType: "lproj"),
                  let catalogue = Bundle(path: path) else { continue }
            for (key, (token, count)) in expected {
                let value = catalogue.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertEqual(value.components(separatedBy: token).count - 1, count,
                               "\(lang.lprojName): \(key) → \(value)")
            }
        }
    }

    /// Non-Portuguese catalogues must actually say something different, or the
    /// entry is a copy-paste that only looks translated. Brand names and the
    /// languages that legitimately share a word with Portuguese are excluded.
    func testTheTranslationsAreNotJustThePortugueseAgain() throws {
        let appBundle = Bundle(for: LocalizationManager.self)
        // "Mais" is French for "but"; "Aberto"/"Fechado" are ordinary Spanish
        // and Italian cognates away by one letter — so this checks the sentence,
        // where an untranslated entry is unambiguous.
        let key = "Não consegui carregar o modelo %@."
        for lang in AppLanguage.allCases where lang.lprojName != "pt-BR" {
            guard let path = appBundle.path(forResource: lang.lprojName, ofType: "lproj"),
                  let catalogue = Bundle(path: path) else { continue }
            XCTAssertNotEqual(catalogue.localizedString(forKey: key, value: nil, table: nil), key,
                              "\(lang.lprojName) still shows the Portuguese sentence")
        }
    }
}
