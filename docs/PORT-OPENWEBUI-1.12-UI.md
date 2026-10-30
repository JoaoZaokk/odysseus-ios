# Porte: correções de UI do OpenWebUI-iOS 1.12 para o Odysseus

Escrito em 30/10/2026. Fonte: `~/Projetos/OpenWebUI-iOS`, commit `0b13e3d`
("feat: 1.12 (23)"), já no GitHub. Os dois apps nasceram do mesmo esqueleto
(`MessageBubble`, `ChatScreen`, `\.theme`, `Font.ody`, MarkdownUI), então quase
tudo entra por cópia + ajuste. Cada item diz: o defeito, a causa medida, o que o
OpenWebUI fez, onde está lá, onde cai aqui e o que muda no caminho.

Pisos daqui: **iOS 17 / macOS 14** (o OpenWebUI é iOS-only). Tudo abaixo foi
escrito sem API de iOS 18+, mas o que é UIKit precisa de `#if os(iOS)`.

Ordem sugerida: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9. Os itens 1–3 são defeito
de verdade (o Odysseus tem a mesma estrutura que quebrou lá); 4–9 são
acabamento e recurso.

---

## 1. Conversa longa pula para trás quando a resposta termina (iOS 18)

**Defeito (relato zh_CN, iPhone 15 Pro Max, iOS 18.1):** numa conversa longa,
no instante em que a resposta termina a tela salta dezenas de mensagens para
cima — sempre para o mesmo ponto ("Parte 22" no stub).

**Causa medida:** no iOS 18 um `LazyVStack` re-posiciona TODAS as linhas pela
altura *estimada* quando um filho entra ou sai do stack. No fim da resposta
entravam follow-ups / opções; o stack inteiro era recalculado e a âncora
`"bottom"` (posta pela soma das alturas estimadas) caía no meio da conversa.

**O Odysseus tem exatamente isso:** `Features/Chat/ChatScreen.swift:108-140` —
`LazyVStack` com `ChatNoticeBanner`, `AskUserCard` e o `toolStatus` **dentro**
do stack (aparecem/somem justamente no fim do turno), sentinela
`Color.clear.id("bottom")` e `scrollToBottom` animado a cada token.

**O que fazer (OpenWebUI `App/Features/Chat/ChatScreen.swift:198-364`):**

1. Tirar do `LazyVStack` tudo que aparece no fim do turno (`vm.notices`,
   `vm.pendingAsk`, `vm.toolStatus`) para um `VStack` comum logo abaixo,
   ainda dentro do `ScrollView`, e só quando não vazio:
   ```swift
   LazyVStack(spacing: 16) { ForEach(...) { MessageBubble(...).id(msg.id) } }
   // Outside the lazy stack on purpose: on iOS 18 a child coming or going
   // inside a LazyVStack re-placed every row by its estimated height.
   if !vm.notices.isEmpty || vm.pendingAsk != nil || vm.toolStatus != nil {
       VStack(spacing: 16) { /* notices, AskUserCard, toolStatus */ }
   }
   Color.clear.frame(height: 1).id("bottom")
   ```
2. Por token: seguir a sentinela **sem animação** (animado por token dá
   rubber-band) e só se o usuário não rolou para cima:
   ```swift
   .onChange(of: vm.messages.last?.content) { _, _ in
       if followsEnd { proxy.scrollTo("bottom", anchor: .bottom) }
   }
   ```
3. No fim do stream, assentar na última mensagem repetindo enquanto o layout
   termina:
   ```swift
   .onChange(of: vm.isStreaming) { _, streaming in
       if !streaming, !userScrolledAway { settleAtEnd(proxy) }
   }
   private func settleAtEnd(_ proxy: ScrollViewProxy) {
       followEnd(proxy)
       for delay in [0.15, 0.4, 0.8] {
           DispatchQueue.main.asyncAfter(deadline: .now() + delay) { followEnd(proxy) }
       }
   }
   private func followEnd(_ proxy: ScrollViewProxy) {
       guard let last = vm.messages.last?.id else { return }
       proxy.scrollTo(last, anchor: .bottom)
   }
   ```
4. `userScrolledAway` / `pinnedToBottom`: sentinela com `GeometryReader` +
   `PreferenceKey` no espaço `"chatScroll"` e um `DragGesture` simultâneo que
   marca `userScrolledAway = true` (OpenWebUI `ChatScreen.swift:246-262`).
   Mandar mensagem ou focar o campo re-prende no fim. Botão "Ir para o fim"
   (chevron) aparece só quando solto — opcional, está em `:302-324`.

**Testado e reprovado lá (não repetir):** `scrollPosition(id:)` e
`defaultScrollAnchor(.bottom)` — resolvem no iOS 27 e **pioram** no iOS 18
(seguram a tela na primeira mensagem).

**Teste:** UI test com conversa de ~80 mensagens longas (stub
`STUB_LONG_CHAT=1` no OpenWebUI), mandar uma, esperar o fim do stream e
conferir que a última mensagem está visível. Rodar no **iOS 18.x** — no 27 o
defeito não aparece. Stub reiniciado entre suítes (sujeira = falsa falha).

## 2. Conversa longa abre em branco / parada no meio

**Causa:** ao chegar o histórico inteiro, o pulo mirava a sentinela posta por
alturas estimadas; o fim ficava acima da tela.

**O que fazer:** quando `messages.count` cresce mais de 2 de uma vez é
histórico, não envio — pular sem animação para a **última mensagem** e repetir
uma vez depois do layout:
```swift
.onChange(of: vm.messages.count) { old, new in
    pinnedToBottom = true; userScrolledAway = false
    if new - old > 2 { jumpToEnd(proxy) } else { settleAtEnd(proxy) }
}
private func jumpToEnd(_ proxy: ScrollViewProxy) {
    guard let last = vm.messages.last?.id else { return }
    proxy.scrollTo(last, anchor: .bottom)
    for delay in [0.15, 0.4] {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { proxy.scrollTo(last, anchor: .bottom) }
    }
}
```
Aqui o `.onChange(of: vm.messages.count)` chama `scrollToBottom` animado —
trocar por isto.

## 3. `MessageBubble` redesenhando a conversa inteira a cada token

OpenWebUI: `struct MessageBubble: View, Equatable` com `==` comparando só o que
muda o desenho (id, content, thinking, isStreaming, statusText…) e
`.equatable()` no `ForEach`. Closures ficam fora da comparação. Numa conversa
longa isso tira o custo de cada token de O(n) para O(1). Aqui o bubble lê
`SpeechManager` e `UIVisibility` por ambiente/observado — esses continuam
invalidando quando mudam, o que é o desejado.

## 4. "Selecionar texto" — trecho de resposta não selecionável

**Defeito:** no iOS, `.textSelection(.enabled)` no `Markdown` só copia o bloco
inteiro; não há seleção por intervalo. O Odysseus usa exatamente isso
(`MessageBubble.swift:113,121`).

**O que fazer:** item "Selecionar texto" no menu da mensagem abre uma sheet
com `UITextView` não editável e selecionável (seleção por intervalo nativa).
OpenWebUI `App/Features/Chat/SelectableTextSheet.swift` (58 linhas, copiar).
`#if os(iOS)` — no macOS a seleção do SwiftUI já é por intervalo, não mostrar
o item lá.

## 5. HTML de layout impresso como texto + quebras de linha sumindo

**Defeito:** modelos mandam `<div style="text-align:center">`, `<br>`,
`<center>`; o web descarta, o MarkdownUI imprimia as tags. E uma quebra de
linha simples (soft break) virava espaço — o web quebra.

**O que fazer:**
- Copiar `App/Features/Chat/ReplyMarkup.swift` (60 linhas). Remove tags de
  layout, `<br>` vira `\n`, nunca toca código (cerca ou inline), e um `<svg>`
  solto vira bloco ```` ```svg ```` (desenhado pelo item 6).
- `Markdown(ReplyMarkup.clean(message.content)).markdownSoftBreakMode(.lineBreak)`
- Testes: `OpenWebUITests/ReplyMarkupTests.swift` (8 casos) — portar inteiro.

## 6. Mermaid, SVG e prévia de HTML desenhados

**O que o web faz:** desenha ```` ```mermaid ````, SVG e prévia de HTML. O app
mostrava o código cru.

**OpenWebUI:**
- `App/Features/Chat/RichBlocks.swift` (271 linhas):
  - `RichBlock` (mermaid / svg);
  - `page(_:code:theme:)` monta o HTML;
  - `palette(for:)` + `hueDistance` dão as cores do gráfico a partir do accent
    do tema. Primeiro filtrei por contraste e a paleta esvaziou; por distância
    de matiz funciona;
  - `WebSnippet` é um `WKWebView` que mede a altura por `postMessage` e já tem
    ramo `NSViewRepresentable` para o macOS;
  - `RichBlockView` espera 0,7 s de debounce durante o stream;
  - `HTMLBlockView` mostra o código, com um botão "Visualizar" que abre a
    prévia.
- `App/Resources/Web/mermaid.min.js` é o **mermaid 11.4.1 embutido** (2,6 MB,
  sha256 `a43bc1af…`). Funciona offline e não busca nada fora.
- `CodeBlockView` roteia pela linguagem da cerca: mermaid/svg vão para
  `RichBlockView`, html para `HTMLBlockView`.

**Aqui:** o `Markdown` do bubble não tem `markdownBlockStyle(\.codeBlock)`
próprio. É preciso criar um, ou adaptar o `CodeBlockView` do OpenWebUI, e rotear
igual.
- **Escuro/claro:** a página recebe as cores do tema por variáveis CSS
  (`chartVariables`). Conferir os 17 temas daqui.
- **Pacote:** `mermaid.min.js` entra nos **dois** alvos (`project.yml`,
  resources).
- **Navegação:** o `WKWebView` bloqueia toda navegação
  (`decidePolicyFor` → `.cancel`). Manter.

## 7. Opções escritas pelo modelo viram botões

Modelos escrevem escolhas com marcas de rádio/caixa (`🔘 A`, `- [ ] B`, `☐ C`).
OpenWebUI `App/Features/Chat/ReplyOptions.swift`: `ReplyOptions.parse(_:)` pega
o último grupo de ≥2 opções da última resposta **já terminada** (ignora código;
caixa `[ ]` só conta sob uma pergunta, senão é lista de tarefas);
`ReplyOptionsList` desenha botões
"Responder" que mandam a opção como próxima mensagem. Fica fora do
`LazyVStack` (item 1). Teste: `OpenWebUITests/ReplyOptionsTests.swift`.
Aqui convive com o `AskUserCard` (pergunta formal do agente): se houver
`pendingAsk`, não mostrar as opções parseadas.

## 8. Raciocínio: uma linha viva e "Pensou por N s"

Hoje aqui: `DisclosureGroup` com rótulo "Pensando…"/"Raciocínio"
(`MessageBubble.swift:153-169`).

OpenWebUI `ReasoningDisclosure` (`MessageBubble.swift:451+` lá): durante o
stream mostra `Pensando · <linha atual>` (última frase não vazia do
raciocínio, uma linha, troca com fade); ao terminar, `🧠 Pensou por N s`
(cronometrado do 1º token de raciocínio ao 1º de conteúdo). Toque expande o
texto inteiro. `static func currentLine(_:)` testado em
`OpenWebUITests/ThinkingLineTests.swift`. Mantém o interruptor
`ui.isOn(.thinking)` daqui.

## 9. Visual: resposta sem balão, vinheta, brilho, faixa de leitura

O dono aprovou cada um destes vendo no aparelho; detalhes de intensidade
foram ajustados tema a tema.

- **Estilo da resposta** (Ajustes › Aparência › "Estilo da resposta"):
  `ReplyStyle` = automático / sem balão / balão / vidro / faixa de leitura,
  `@AppStorage("reply.style")`. Automático = sem balão, exceto temas com
  gravura (Hermes, lá) que usam faixa de leitura. O dono **não** quer "sem
  balão" em tema com gravura: vidro ou faixa.
  - Resposta sem balão: padding top 12 / bottom 15.
  - Código: `App/Features/Shared/ThemeVignette.swift` (`ReplyStyle`,
    `ReadingLane`, `ReplyStylePicker`) e `MessageBubble`
    (`replyStyle`/`replyBoxed`/`replyFill`).
- **Vinheta** (`ThemeVignette`): luz de dois cantos opostos (topo-direita,
  base-esquerda) mais a borda levemente escura; gradientes estáticos, sem custo
  por quadro.
  - Intensidade por tema (`theme.vignette`; 0 desliga), na cor `theme.glow` no
    escuro e branca no claro.
  - Regra do dono: **subliminar**. Se dá pra notar, está forte.
  - Aqui convive com `Config/Backgrounds.swift` (estrelas/aurora): a vinheta vai
    por cima do fundo animado e por baixo do conteúdo.
- **Brilho atrás da mensagem** (`BubbleEffect`): halo neutro (branco no escuro,
  sombra preta no claro). O dono gostou do brilho.
- **Fundo como camada**: `ThemeCanvas` no lugar de `theme.bg` (bg + gravura +
  vinheta), com a gravura **atrás** do conteúdo. Antes era overlay e aparecia
  através dos balões.
- **Faixa do composer**: tirar o `.background(theme.bg)` do composer. Era uma
  faixa chapada cortando a vinheta.
- **Fade nas bordas**: `.scrollEdgeFade()` faz a conversa sumir suave sob as
  barras (máscara linear, 28 pt em cima e 14 pt embaixo).
- **Auditoria de cor/contraste/raio**: foi feita por agente (sonnet) tema a
  tema no OpenWebUI, mais o enum `Radius`. Os valores **não** servem aqui, porque
  os temas daqui são os do web do Odysseus. Repetir o método: um verificador por
  tema, com contraste fg/bg, bubble e accent ≥ 4,5:1.
- **Campos novos no `Theme`**: `vignette: Double`, `glow: Color`, e `hex` se
  for usar a paleta do item 6.

## Fora de UI, mas no mesmo pacote (opcional)

- **Fundo do chat por imagem** (`ChatWallpaper.swift`, 125 linhas + teste):
  aqui há fundos animados; avaliar se o dono quer.
- **Estouro de contexto nomeado + "Resumir conversa e continuar"**:
  - Lá é `ChatViewModel.isContextOverflow`, `summaryPieces` (12k caracteres),
    `summarizeAndRetry`, e `.contextFull` no cliente quando
    `finish_reason == "length"` sem saída.
  - Formatos reais de erro:
    - GLM: HTTP 400 "Prompt exceeds max length".
    - MiMo: resposta vazia com `finish_reason: "length"`, **sem erro**.
  - Aqui o servidor monta o contexto (`/api/chat_stream`), então primeiro ver
    o que ele devolve ao estourar.
- **Nome do aparelho no relatório de bug**: `BugReport.deviceLabel` →
  "iPhone 15 Pro Max (iPhone16,2)". Encaixa no `BugReport.make` daqui.

## Strings novas (entram nos 43 catálogos, por script com assert)

UI: `Selecionar texto`, `Estilo da resposta`, `Automático`, `Sem balão`,
`Balão`, `Vidro`, `Faixa de leitura`, `Pensando`, `Pensou por %@ s`,
`Visualizar`, `Responder`. Opcionais: `Fundo do chat`, `Remover fundo do
chat`, `Não foi possível usar esta imagem.`, as 4 do resumo de contexto.
Traduções prontas nos 44 catálogos do OpenWebUI (`App/Resources/*.lproj`) —
reaproveitar por locale.

## Testes do OpenWebUI que vêm junto

`ReplyMarkupTests`, `ReplyOptionsTests`, `ThinkingLineTests`,
`ReplyStyleTests`, e o UI test de conversa longa / selecionar texto em
`OpenWebUIUITests/StubScreensUITests.swift`. Verificação final = walkthrough
no simulador **iOS 18** e no 27 (o item 1 só aparece no 18).
