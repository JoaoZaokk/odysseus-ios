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
        // 1.13 — reading messages aloud, providers by key, models by kind
        "Chat", "Vídeo", "Voz (TTS)", "Transcrição (STT)", "Áudio ao vivo", "Embeddings",
        "%@ — lendo com a voz do aparelho.", "Parar leitura", "Ouvir mensagem",
        "URL personalizada", "Chave reconhecida: %@", "Não aparece no seletor do chat.",
        "A Gemini não tem /audio/speech nem /audio/transcriptions: estes modelos não servem de voz do servidor.",
        "Música", "Usar para chat",
        "Cadastrado como Imagem: os modelos de chat deste endpoint não aparecem no seletor do chat.",
        // Visual-defects round: Tema's INTERFACE section and the labels that
        // VoiceOver reads for glyph-only markers (task state, pin, favourite).
        "Interface", "Pausada", "Ativa", "Fixada", "Favorito",
        // Deep Research panel: mode chips, menu labels, Start, the past-research
        // row. Those were English literals in a Portuguese-keyed app, so the
        // panel read "Product / Compare / Rounds / Start" in every language.
        // "Comparar", "Busca", "Modelo", "Padrão" and "· %lld rodadas" already
        // existed and are pinned because the panel now depends on them.
        "Produto", "Passo a passo", "Checagem de fatos", "Rodadas", "Endpoint",
        "Iniciar", "sem resultados", "%lld fontes", "1 fonte", "· 1 rodada",
        "Comparar", "Busca", "Modelo", "Padrão", "· %lld rodadas",
        // 1.15 — the composer's "+" menu and the voice notice that replaced
        // "(sem resposta)", with the web switch's own settings section.
        "Mais opções", "A busca na web está desligada",
        "Tentei pesquisar para responder, mas a busca está desligada na voz.",
        "Não consegui responder a isso por voz.", "Busca na web",
        "A IA pode pesquisar na web durante a conversa por voz. Ligado: respostas atualizadas, um pouco mais lentas. Desligado: responde só com o que já sabe.",
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
                        "Não consegui carregar o modelo %@.": ("%@", 1),
                        "%@ — lendo com a voz do aparelho.": ("%@", 1),
                        "Chave reconhecida: %@": ("%@", 1),
                        "%lld fontes": ("%lld", 1),
                        "· %lld rodadas": ("%lld", 1)]
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

    // MARK: - Deep Research panel

    /// The Deep Research panel's strings, with what English must read. English
    /// is the reference language: before this, these were English *keys* whose
    /// pt-BR value was also English, so the Portuguese UI showed them verbatim.
    private let deepResearchEnglish: [String: String] = [
        "Produto": "Product", "Passo a passo": "How-to", "Checagem de fatos": "Fact-check",
        "Comparar": "Compare", "Rodadas": "Rounds", "Busca": "Search", "Endpoint": "Endpoint",
        "Modelo": "Model", "Padrão": "Default", "Iniciar": "Start", "sem resultados": "no results",
        "%lld fontes": "%lld sources", "1 fonte": "1 source",
        "· %lld rodadas": "· %lld rounds", "· 1 rodada": "· 1 round",
    ]

    func testDeepResearchPanelReadsEnglishInEnglish() throws {
        let appBundle = Bundle(for: LocalizationManager.self)
        let path = try XCTUnwrap(appBundle.path(forResource: "en", ofType: "lproj"))
        let en = try XCTUnwrap(Bundle(path: path))
        for (key, english) in deepResearchEnglish {
            XCTAssertEqual(en.localizedString(forKey: key, value: nil, table: nil), english, key)
        }
    }

    /// An entry that still says the Portuguese word is a copy-paste that only
    /// looks translated. The exceptions are real: "Endpoint" is the technical
    /// term most languages keep, and Spanish "Iniciar" / Italian "fonte" are
    /// the same word as the Portuguese.
    func testDeepResearchPanelIsTranslatedInEveryLanguage() throws {
        let appBundle = Bundle(for: LocalizationManager.self)
        let sameWordIsRight: [String: Set<String>] = [
            "Endpoint": Set(AppLanguage.allCases.map(\.lprojName)),
            "Iniciar": ["es"],
            "1 fonte": ["it"],
        ]
        let panelKeys = ["Produto", "Passo a passo", "Checagem de fatos", "Rodadas", "Endpoint",
                         "Iniciar", "sem resultados", "%lld fontes", "1 fonte", "· 1 rodada"]
        for lang in AppLanguage.allCases where lang.lprojName != "pt-BR" {
            guard let path = appBundle.path(forResource: lang.lprojName, ofType: "lproj"),
                  let catalogue = Bundle(path: path) else { XCTFail("\(lang.rawValue): no catalogue"); continue }
            for key in panelKeys where !(sameWordIsRight[key]?.contains(lang.lprojName) ?? false) {
                XCTAssertNotEqual(catalogue.localizedString(forKey: key, value: nil, table: nil), key,
                                  "\(lang.lprojName) still shows the Portuguese \(key)")
            }
        }
    }

    /// The server's category ids are the left side of the tuples; the label on
    /// the chip is a catalogue key and must not be the other way round.
    @MainActor
    func testModesKeepTheWireIdsAndLabelThemInPortuguese() {
        XCTAssertEqual(DeepResearchVM.modes.map(\.0), ["auto", "product", "comparison", "howto", "factcheck"])
        XCTAssertEqual(DeepResearchVM.modes.map(\.1),
                       ["Auto", "Produto", "Comparar", "Passo a passo", "Checagem de fatos"])
        XCTAssertEqual(DeepResearchVM.modeLabel(forCategory: "howto"), "Passo a passo")
        XCTAssertEqual(DeepResearchVM.modeLabel(forCategory: "comparison"), "Comparar")
        XCTAssertNil(DeepResearchVM.modeLabel(forCategory: "something-new"))
    }

    /// "1 fontes" / "1 rounds" is what a bare `%lld` produces for the one count
    /// users actually pick ("Rounds: 1"), so the singular has its own key.
    @MainActor
    func testCountsReadRightInTheSingularAndThePlural() {
        let previous = LocalizationManager.shared.active
        defer { Bundle.setAppLanguage(previous) }

        Bundle.setAppLanguage(.en)
        XCTAssertEqual(DeepResearchVM.sourcesText(1), "1 source")
        XCTAssertEqual(DeepResearchVM.sourcesText(14), "14 sources")
        XCTAssertEqual(DeepResearchVM.roundsText(1), "· 1 round")
        XCTAssertEqual(DeepResearchVM.roundsText(3), "· 3 rounds")

        Bundle.setAppLanguage(.ptBR)
        XCTAssertEqual(DeepResearchVM.sourcesText(1), "1 fonte")
        XCTAssertEqual(DeepResearchVM.sourcesText(14), "14 fontes")
        XCTAssertEqual(DeepResearchVM.roundsText(1), "· 1 rodada")
        XCTAssertEqual(DeepResearchVM.roundsText(3), "· 3 rodadas")
    }
}
