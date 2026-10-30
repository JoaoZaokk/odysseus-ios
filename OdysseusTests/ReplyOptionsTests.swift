import XCTest
@testable import Odysseus

/// GPT and Claude ask with buttons (a tool of their platform); a model behind
/// Odysseus has none in chat mode, so a model asked for one writes the options out — one per line with a
/// radio mark, as mimo-v2.6-flash did on 2026-10-29. The last such group in a
/// reply becomes buttons that send the option as the next message.
final class ReplyOptionsTests: XCTestCase {

    private let mimo = """
    **Qual dos dias você mais gostaria de adaptar ou aprofundar?**

    🔘 **Dia 1** - Quero mais detalhes sobre Alfama, comida ou cultura
    🔘 **Dia 2** - Quero dicas de Belém e passeio no Tejo
    🔘 **Dia 3** - Quero focar em Sintra ou nos miradouros

    > 💡 **Clique no botão acima e me responda!**
    """

    func testRadioMarkedLinesBecomeOptions() {
        XCTAssertEqual(ReplyOptions.parse(mimo), [
            "Dia 1 - Quero mais detalhes sobre Alfama, comida ou cultura",
            "Dia 2 - Quero dicas de Belém e passeio no Tejo",
            "Dia 3 - Quero focar em Sintra ou nos miradouros",
        ])
    }

    func testAnOrdinaryListIsNotAQuestion() {
        XCTAssertEqual(ReplyOptions.parse("Leve:\n\n- protetor solar\n- garrafa d'água\n- tênis"), [])
    }

    func testCheckboxesCountOnlyUnderAQuestion() {
        XCTAssertEqual(ReplyOptions.parse("Tarefas:\n- [ ] comprar pão\n- [ ] lavar o carro"), [])
        XCTAssertEqual(ReplyOptions.parse("Qual prefere?\n- [ ] Praia\n- [ ] Montanha"), ["Praia", "Montanha"])
    }

    func testOneOptionIsNoChoice() {
        XCTAssertEqual(ReplyOptions.parse("Quer continuar?\n🔘 Sim"), [])
    }

    func testOptionsInsideCodeAreLeftAlone() {
        XCTAssertEqual(ReplyOptions.parse("```\n🔘 a\n🔘 b\n```"), [])
    }
}
