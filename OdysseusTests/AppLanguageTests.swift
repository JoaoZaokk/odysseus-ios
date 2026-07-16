import XCTest
@testable import Odysseus

final class AppLanguageTests: XCTestCase {

    func testPortugueseVariantsMapToPtBR() {
        XCTAssertEqual(AppLanguage.match(systemCode: "pt-BR"), .ptBR)
        XCTAssertEqual(AppLanguage.match(systemCode: "pt-PT"), .ptBR)
        XCTAssertEqual(AppLanguage.match(systemCode: "pt"), .ptBR)
    }

    func testChineseScriptDetection() {
        XCTAssertEqual(AppLanguage.match(systemCode: "zh-Hans-CN"), .zhHans)
        XCTAssertEqual(AppLanguage.match(systemCode: "zh-Hant-TW"), .zhHant)
        XCTAssertEqual(AppLanguage.match(systemCode: "zh-HK"), .zhHK)
        XCTAssertEqual(AppLanguage.match(systemCode: "zh-MO"), .zhHK)
        XCTAssertEqual(AppLanguage.match(systemCode: "yue-HK"), .zhHK)
        XCTAssertEqual(AppLanguage.match(systemCode: "zh"), .zhHans)
    }

    func testGermanRegionalVariants() {
        XCTAssertEqual(AppLanguage.match(systemCode: "de-AT"), .deAT)
        XCTAssertEqual(AppLanguage.match(systemCode: "de-CH"), .deCH)
        XCTAssertEqual(AppLanguage.match(systemCode: "de-DE"), .de)
        XCTAssertEqual(AppLanguage.match(systemCode: "de"), .de)
    }

    func testLegacyIndonesianCode() {
        // iOS may report Indonesian as legacy "in".
        XCTAssertEqual(AppLanguage.match(systemCode: "in"), .ind)
        XCTAssertEqual(AppLanguage.match(systemCode: "id-ID"), .ind)
    }

    func testUnknownCodeReturnsNil() {
        XCTAssertNil(AppLanguage.match(systemCode: "xx-YY"))
    }

    func testRTLSet() {
        XCTAssertTrue(AppLanguage.ar.isRTL)
        XCTAssertTrue(AppLanguage.fa.isRTL)
        XCTAssertTrue(AppLanguage.ur.isRTL)
        XCTAssertTrue(AppLanguage.ps.isRTL)
        XCTAssertTrue(AppLanguage.he.isRTL)
        XCTAssertTrue(AppLanguage.ug.isRTL)
        XCTAssertFalse(AppLanguage.en.isRTL)
        XCTAssertFalse(AppLanguage.ptBR.isRTL)
        XCTAssertFalse(AppLanguage.th.isRTL)   // Thai is LTR
        XCTAssertFalse(AppLanguage.bo.isRTL)   // Tibetan is LTR
    }

    func testNewLanguagesMatch() {
        XCTAssertEqual(AppLanguage.match(systemCode: "fi-FI"), .fi)
        XCTAssertEqual(AppLanguage.match(systemCode: "sv-SE"), .sv)
        XCTAssertEqual(AppLanguage.match(systemCode: "lv-LV"), .lv)
        XCTAssertEqual(AppLanguage.match(systemCode: "lb-LU"), .lb)
        XCTAssertEqual(AppLanguage.match(systemCode: "th-TH"), .th)
        XCTAssertEqual(AppLanguage.match(systemCode: "he-IL"), .he)
        XCTAssertEqual(AppLanguage.match(systemCode: "iw"), .he)   // legacy Hebrew code
        XCTAssertEqual(AppLanguage.match(systemCode: "ug-CN"), .ug)
        XCTAssertEqual(AppLanguage.match(systemCode: "bo-CN"), .bo)
    }

    /// Regression: pt-BR used to return nil here, on the theory that the base
    /// language needs no table. It does. SwiftUI resolves `Text()` against the
    /// environment locale, and with no pt-BR.lproj it fell back to
    /// CFBundleDevelopmentRegion (en) — Brazilians got the English build.
    func testPtBRShipsAnLprojLikeEveryOtherLanguage() {
        XCTAssertEqual(AppLanguage.ptBR.lprojName, "pt-BR")
        XCTAssertEqual(AppLanguage.ja.lprojName, "ja")
    }

    /// Every language, pt-BR included, must ship its .lproj in the app bundle.
    func testAllShippedLanguagesHaveLproj() {
        let appBundle = Bundle(for: LocalizationManager.self)
        for lang in AppLanguage.allCases {
            guard let lproj = lang.lprojName else {
                XCTFail("\(lang.rawValue) has no lprojName — it will fall back to English")
                continue
            }
            XCTAssertNotNil(appBundle.path(forResource: lproj, ofType: "lproj"),
                            "faltando \(lproj).lproj no bundle")
        }
    }
}
