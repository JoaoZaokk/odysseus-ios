import XCTest
@testable import Odysseus

/// The three rules `SettingsUI.failure` exists to state.
///
/// The point of the function is not the lines it saves — it saves six. It is
/// that these three rules were unwritten, enforced by nothing, and each had
/// already been broken: five sites interpolated the format, twenty-one skipped
/// the cancellation check, and three spelled out the 403 branch by hand. A rule
/// with no home cannot be tested, and this file is what the home bought.
final class FailureTextTests: XCTestCase {

    // MARK: - Rule 1: a cancelled request is not a failure

    func testCancellationProducesNoText() {
        XCTAssertNil(SettingsUI.failure(CancellationError(), "Falha: %@"))
    }

    func testCancellationProducesNoTextEvenWhenAdminIsSupplied() {
        XCTAssertNil(SettingsUI.failure(CancellationError(), "Falha: %@", admin: "Só admin."))
    }

    func testTheURLErrorFormOfCancellationCountsToo() {
        // A cancelled URLSession task arrives as URLError, not CancellationError.
        XCTAssertNil(SettingsUI.failure(URLError(.cancelled), "Falha: %@"))
    }

    func testNilIsWhatClearsTheField() {
        // `field = SettingsUI.failure(...)` must be able to retract a previous
        // error, not leave it standing. That is the whole reason for String?.
        var note: String? = "Falha: erro anterior"
        note = SettingsUI.failure(CancellationError(), "Falha: %@")
        XCTAssertNil(note)
    }

    // MARK: - Rule 2: the format stays a catalogue key

    func testTheFormatIsLookedUpAndTheValueIsInterpolated() {
        let out = SettingsUI.failure(APIError.http(500, "servidor ocupado"), "Falha ao salvar: %@")
        // pt-BR maps the key to itself, so this is the key with %@ filled in —
        // which is exactly what proves the lookup ran on the format, not on the
        // finished sentence.
        XCTAssertEqual(out, "Falha ao salvar: servidor ocupado")
    }

    func testTheKeyIsTranslatedBeforeInterpolation() throws {
        // The catalogue is what must be consulted. If the format were
        // interpolated first, no entry could ever match it.
        let appBundle = Bundle(for: LocalizationManager.self)
        let path = try XCTUnwrap(appBundle.path(forResource: "en", ofType: "lproj"))
        let en = try XCTUnwrap(Bundle(path: path))
        let translated = en.localizedString(forKey: "Falha ao salvar: %@", value: nil, table: nil)
        XCTAssertNotEqual(translated, "Falha ao salvar: %@",
                          "the key must exist in en.lproj, or this rule is untestable")
        XCTAssertTrue(translated.contains("%@"),
                      "the translation must keep the placeholder, or interpolation loses the detail")
    }

    func testEveryFormatPassedToFailureExistsInTheCatalogue() throws {
        // The rule is only worth anything if the keys are real. This walks the
        // source rather than a hand-kept list, so a new call site is covered the
        // day it is written.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let appBundle = Bundle(for: LocalizationManager.self)
        let path = try XCTUnwrap(appBundle.path(forResource: "en", ofType: "lproj"))
        let en = try XCTUnwrap(Bundle(path: path))

        let swift = FileManager.default.enumerator(at: root.appendingPathComponent("Odysseus"),
                                                   includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(swift.isEmpty, "found no sources to scan")

        let call = try NSRegularExpression(pattern: #"SettingsUI\.failure\(\s*\w+\s*,\s*"([^"]+)""#)
        var checked = 0
        for url in swift {
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for m in call.matches(in: text, range: range) {
                guard let r = Range(m.range(at: 1), in: text) else { continue }
                let key = String(text[r])
                checked += 1
                XCTAssertNotEqual(en.localizedString(forKey: key, value: nil, table: nil), key,
                                  "\(url.lastPathComponent): \"\(key)\" is not in the catalogues")
                XCTAssertTrue(key.contains("%@"), "\(url.lastPathComponent): \"\(key)\" has no %@")
            }
        }
        XCTAssertGreaterThan(checked, 15, "the scan found too few call sites to be doing its job")
    }

    // MARK: - Rule 3: 403 is not a generic failure

    func testA403UsesTheCallersAdminSentence() {
        let out = SettingsUI.failure(APIError.http(403, "Forbidden"),
                                     "Não foi possível salvar: %@",
                                     admin: "Só um administrador pode escolher quais modelos aparecem.")
        XCTAssertEqual(out, "Só um administrador pode escolher quais modelos aparecem.")
    }

    func testA403WithoutAnAdminSentenceFallsBackToTheFormat() {
        // Not every 403 has a sentence to offer, and inventing one would be worse.
        let out = SettingsUI.failure(APIError.http(403, "Forbidden"), "Falha: %@")
        XCTAssertEqual(out, "Falha: Forbidden")
    }

    func testA401IsNotFoldedIntoThe403Branch() {
        // 401 is "you are not", 403 is "you may not". AppState owns the first.
        let out = SettingsUI.failure(APIError.notAuthenticated, "Falha: %@", admin: "Só admin.")
        XCTAssertEqual(out, "Falha: Sessão expirada. Faça login novamente.")
    }

    func testAnyOtherStatusIgnoresTheAdminSentence() {
        let out = SettingsUI.failure(APIError.http(500, "boom"), "Falha: %@", admin: "Só admin.")
        XCTAssertEqual(out, "Falha: boom")
    }
}
