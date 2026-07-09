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
        XCTAssertFalse(AppLanguage.en.isRTL)
        XCTAssertFalse(AppLanguage.ptBR.isRTL)
    }

    func testPtBRHasNoLproj() {
        XCTAssertNil(AppLanguage.ptBR.lprojName)
        XCTAssertEqual(AppLanguage.ja.lprojName, "ja")
    }

    /// Every language except pt-BR must ship its .lproj in the app bundle.
    func testAllShippedLanguagesHaveLproj() {
        let appBundle = Bundle(for: LocalizationManager.self)
        for lang in AppLanguage.allCases {
            guard let lproj = lang.lprojName else { continue }
            XCTAssertNotNil(appBundle.path(forResource: lproj, ofType: "lproj"),
                            "faltando \(lproj).lproj no bundle")
        }
    }
}
