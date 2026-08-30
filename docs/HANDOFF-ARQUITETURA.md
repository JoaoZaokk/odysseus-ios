# Handoff — fase de arquitetura, encerrada

Estado em 2026-08-30, fim da rodada 3. Tudo abaixo está em `main`, **1.9 / build 23**
(macOS build 17). **184 testes**, iOS e macOS compilando sem aviso. Zero issues abertas,
zero PRs abertos.

## O que aconteceu nesta rodada

Doze candidatos a aprofundamento, explorados por seis agentes independentes por subsistema,
cada um entregue a um refutador adversarial cujo padrão era REFUTADO.

| | |
|---|---|
| Sobreviveram limpos | **2** |
| Sobreviveram em escopo menor | **4** |
| Mortos | **6** |

Os dois primeiros e os escopos que sobreviveram das dez refutações foram implementados em
[PR #29](https://github.com/JoaoZaokk/odysseus-ios/pull/29) e no commit seguinte.

**A taxa de refutação é o dado que importa: 10 de 12.** Ela vale para a próxima rodada.

## O que a rodada 3 mudou de estrutural

### O seam de transporte — leia a ADR 0002

`docs/adr/0002-a-transport-seam-under-apiclient.md`.

A ADR 0001 recusou seis protocolos **sobre** a superfície da API e nomeou a lacuna que
nenhum deles atacava: nenhum teste alcançava o `load()` de um view model. Ela mandou
reabrir sobre **um** argumento — um seam cujo segundo adapter é o test double. Foi o que
aconteceu.

`APIClient.init(config:protocolClasses:)`. `nil` é a cadeia da Foundation; o app nunca pede
outra coisa. **Nenhum protocolo é declarado** — `grep -rE "protocol " Odysseus/` continua
vazio, e a premissa da ADR 0001 continua literalmente verdadeira. O seam está **embaixo**
do tipo, não na frente dele.

`OdysseusTests/StubTransport.swift` é o segundo adapter. `AppState.init` repassa o mesmo
parâmetro — não é seam novo, é o mesmo atravessando.

**Duas coisas foram estabelecidas por experimento, não por raciocínio:**

1. Um `URLProtocol` em `configuration.protocolClasses` intercepta **`data(for:)` e
   `bytes(for:)`** — o leitor de SSE é alcançável.
2. `URLProtocol.registerClass` **não** serve: retorna `true` e não alcança uma sessão feita
   de `URLSessionConfiguration.default`, que é o que essas duas são.

### O que continua fora do seam

`ComfyUIClient`, `ModelDownloadManager` e as duas sessões do `VoiceEndpoint` criam
`URLSession` própria. Difusão e o caminho de endpoint de voz seguem sem teste e
precisariam do próprio seam.

## O que sobrou

**Nada agendado.** A issue #20 foi fechada: 12 corrigidas, 3 retratadas (descreviam código
já corrigido pelos PRs #27/#28 antes da lista ser escrita), 61 nunca verificadas. O índice
completo continua em `docs/ROUND2-ACHADOS.md` — se uma das 61 se provar real, ela ganha
issue própria com o fonte conferido, que é a única forma que qualquer uma delas deveria ter
tido.

**Nada pendente.** Os 44 catálogos estão em 617 chaves cada, `plutil` limpo, e **nenhum
valor em português sobrou fora do `pt-BR`** — varrido, não presumido. Os únicos
`valor == chave` restantes são marca e estrangeirismo (`Cookbook`, `Deep Research`, `OK`)
e cinco palavras espanholas que coincidem de verdade com o português.

`main` é a única branch, local e remota.

### A string do barge-in: composta, não inventada

`"Barge-in indisponível: a sessão de áudio está em modo de gravação."` chegou como
placeholder e foi traduzida depois. O método vale mais que o resultado: cada catálogo já
tinha a irmã `"…o microfone não pôde ser aberto."` traduzida e revisada, então o prefixo e
o separador vieram **verbatim** de lá e só a oração depois dos dois-pontos é nova.

Isso preservou sozinho o que se erraria à mão: dois-pontos de largura total em `ja`/`zh`,
dois-pontos com espaço em `fr`, shad em `bo`, danda em `hi`/`bn`, ponto árabe em `ur`, e
`th` sem pontuação final. **`bo` continua marcado para revisão nativa** — a primeira passada
saiu com shad duplo.

### O servidor não roda STT

`docs/PATCH-SERVIDOR-STT-IDIOMA.md` **não é pendência de ninguém.** `stt_provider` nasce
`"disabled"` e nada foi ligado. O ditado vem do reconhecedor da Apple (`.native`, o padrão
do app) ou do whisper.cpp embutido — nunca do servidor. O motor STT `.server` não é caminho
utilizável ali. **Barge-in e VAD são on-device (FluidAudio) e não têm relação com isso** —
não confundir os dois quando algo de voz quebrar.

O documento fica como desenho pronto para o dia em que o STT de servidor for ligado.

### `SettingsUI.failure`: recusado, depois construído

Vale registrar por que a recusa estava errada, porque o erro é de método.

Eu recusei o helper pela conta de linhas: seis linhas economizadas em ~20 call sites.
A conta estava certa e a métrica estava errada. **Linha não é o teste** — o teste que esta
rodada inteira usou é profundidade (alavancagem por unidade de interface) e locality
(o conhecimento mora num lugar só).

O que decidiu foi remedir na métrica certa: das 23 capturas em Settings que escrevem texto
de erro, **2 checavam cancelamento e 21 não**. A divisão é até coerente — cargas guardam,
ações de botão não — mas **nada em lugar nenhum diz isso**, então o próximo `load()` tem
dois exemplos para copiar e vinte e um contraexemplos.

E a varredura que veio junto provou o argumento: **13 sites de falha ainda em
`theme.accent`** que a lista anterior não continha. Corrigir caso a caso não impede o
próximo caso. Uma regra sem casa não pode ser testada — e agora tem onze testes, um deles
varrendo o fonte, então todo call site novo é conferido contra o catálogo no dia em que
é escrito.

## Armadilhas desta base

1. **A chave é o literal em pt-BR.** Reescrever o texto em Swift desativa a tradução em 43
   idiomas, e nada falha. `OdysseusTests/EmailLoginGuideTests.swift` fixa isso para o guia
   de email; o resto ainda depende de varredura.
2. **`Text(x)` com `String` pula a busca.** Precisa ser `Text(LocalizedStringKey(x))`.
   **Texto interpolado nunca vira chave** — tem que ser `L("… %@", x)` na origem. Cinco
   sites quebravam isso e foram corrigidos; a regra continua sem teste.
3. **`perl -CSD -pi -e` com padrão não-ASCII não substitui nada e sai com status 0.** Use
   `python3` com `assert t.count(old) == 1` antes do `replace`.
4. **`Closes #1, #2, #3` fecha só a primeira.** Uma linha `Closes #N` por issue.
5. **SwiftUI renderiza `Int` interpolado como `%lld`, não `%@`.**
6. **`xcodegen generate`** depois de adicionar ou remover arquivo.
7. **`ServerConfig` persiste no simulador.** Um teste que deriva o alvo do que estiver
   salvo está testando a execução anterior — declare a linha de base e restaure. Dois
   testes desta rodada passaram isolados e caíram na suíte por isso.
8. **`git checkout <arquivo>` volta ao último commit, não desfaz só a sabotagem.** Se você
   sabotou de propósito para provar que um teste morde, desfaça pela mesma via que sabotou.
   Aconteceu nesta rodada e levou junto uma mudança não commitada.
9. **A cor de falha é `theme.danger`, nunca `theme.accent`.** `accent` é o `red` do tema, e
   em `forest` ele é `7cb871`, em `terminal` `00ff41`, em `gpt` `949494`. Um `ok ? green :
   accent` pinta os dois ramos de verde nesses temas. Não existe mais nenhum `Color(hex:)`
   fora do `Config/Theme.swift` — se aparecer um, é regressão.

## Método, se houver rodada 4

O que funcionou e vale repetir:

- **Refutador por candidato, com padrão REFUTADO.** Dez de doze caíram. Sem isso, os doze
  teriam virado trabalho.
- **Contagem é o ponto fraco de toda alegação.** Praticamente toda refutação começou por
  recontar, e quase toda recontagem achou erro. Um refutador escreveu um *stack-walk* sobre
  todo `#if/#else/#endif` da árvore em vez de confiar no `grep`, e corrigiu cinco números.
- **Sabotar antes de acreditar.** Toda asserção nova desta rodada foi verificada quebrando
  o código de propósito e vendo o teste cair. Uma delas parecia boa e não mordia.
- **Medir contraste em vez de escolher cor.** `e05a4a` reprovava 4.5:1 em 9 dos 17 temas —
  número que só aparece calculando, e que decidiu sozinho que a cor tinha de ser derivada.
