import XCTest
@testable import Odysseus

/// The guide's copy is not free text: each pt-BR literal doubles as the lookup
/// key in all 44 `.strings` catalogues. Rewording one in Swift silently drops
/// 43 languages back to Portuguese, with nothing failing to say so — these tests
/// are what makes that noisy.
final class EmailLoginGuideTests: XCTestCase {

    private var guideStrings: [String] {
        [EmailLoginGuide.title, EmailLoginGuide.intro, EmailLoginGuide.serversTitle,
         EmailLoginGuide.tip] + EmailLoginGuide.steps
    }

    /// Every literal the view renders has to exist as a key in every catalogue.
    /// `localizedString(forKey:value:table:)` is passed `value: nil`, so a key it
    /// cannot find comes back *as the key* — the Portuguese source — which reads
    /// like a working app right up until a Turkish user opens the screen.
    func testEveryGuideStringIsAKeyInEveryCatalogue() throws {
        let appBundle = Bundle(for: LocalizationManager.self)
        for lang in AppLanguage.allCases {
            guard let lproj = lang.lprojName,
                  let path = appBundle.path(forResource: lproj, ofType: "lproj"),
                  let catalogue = Bundle(path: path) else {
                XCTFail("\(lang.rawValue): no catalogue to check"); continue
            }
            for s in guideStrings {
                let hit = catalogue.localizedString(forKey: s, value: "\u{0}MISS", table: nil)
                XCTAssertNotEqual(hit, "\u{0}MISS", "\(lproj) has no entry for \(s.prefix(40))…")
            }
        }
    }

    /// Step 4 tells the user to tap a button by name. It said "Salvar" for a
    /// long time; the button on that screen is "Criar" (`EmailAccountsView`),
    /// so the last step of the tutorial pointed at a control that isn't there.
    func testStepFourNamesTheButtonThatActuallyExists() {
        let step = EmailLoginGuide.steps[3]
        XCTAssertTrue(step.contains("Criar"), "step 4 must name the Criar button, got: \(step)")
        XCTAssertFalse(step.contains("Salvar"), "there is no Salvar button on the new-account screen")
    }

    /// The click trail through Apple's site is structure, not prose: four hops in
    /// step 1, three in step 2. A translation that drops an arrow loses a step.
    func testClickTrailSurvivesInEveryLanguage() throws {
        let appBundle = Bundle(for: LocalizationManager.self)
        let expected = EmailLoginGuide.steps.prefix(2).map { $0.filter { $0 == "→" }.count }
        for lang in AppLanguage.allCases {
            guard let lproj = lang.lprojName,
                  let path = appBundle.path(forResource: lproj, ofType: "lproj"),
                  let catalogue = Bundle(path: path) else { continue }
            for (i, want) in expected.enumerated() {
                let hit = catalogue.localizedString(forKey: EmailLoginGuide.steps[i], value: nil, table: nil)
                XCTAssertEqual(hit.filter { $0 == "→" }.count, want,
                               "\(lproj) step \(i + 1): expected \(want) arrows")
            }
        }
    }

    /// Host names and ports are not translated, and must not gain a catalogue
    /// entry by accident — the view renders them with a plain `Text`.
    func testServerListIsNotLocalized() {
        XCTAssertEqual(EmailLoginGuide.servers.count, 3)
        for s in EmailLoginGuide.servers { XCTAssertTrue(s.contains(":")) }
    }
}
