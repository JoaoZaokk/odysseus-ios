# Handoff — fase de arquitetura, encerrada; rodada 4 (o review alemão) fechada

Estado em 2026-09-07, fim da rodada 4. Tudo abaixo está em `main`, **1.9 / build 23**
(macOS build 17; o último build subido ao ASC é o **21**, da 1.8 — nada da 1.9 foi
enviado ainda). **234 testes**, iOS e macOS compilando sem aviso. Zero issues abertas,
zero PRs abertos. Catálogos: **44 × 629**.

## Rodada 4 — o review alemão

Uma review na App Store, Alemanha, 2026-09-04, 3 estrelas, sobre a 1.8:
*"ein guter Anfang… aber nicht mehr. Für die Einstellungen fehlt noch viel und die
Sidebar ist noch sehr unaufgeräumt."* Das quatro reviews que as duas apps do dono têm,
três são alemãs e todas de 3 estrelas; a única de 5 é dos EUA. O app nunca pedia
avaliação — só quem se irrita vai à loja sozinho.

O método da rodada 3, de novo: dez investigadores em paralelo (cinco de lacunas de
Ajustes, aba a aba contra o fonte do servidor web; dois de sidebar; dois de i18n; um do
pedido de avaliação), um refutador por achado com padrão REFUTADO, um sintetizador.

| | |
|---|---|
| Achados | **90** |
| Sobreviveram | **80** |
| Refutados | **10** |

**A taxa inverteu: 10 de 12 mortos na rodada 3, 10 de 90 nesta.** Não é frouxidão do
refutador — é que desta vez os achados eram contratos checáveis (rota existe ou não,
chave é lida ou não), não candidatos a refatoração. Metade do "falta muito em Ajustes"
era Ajustes **mentindo**: três rotas de usuário que não existem, um wipe que dá 400,
"Adicionado" verde para host morto, um editor de fallback ligado a chave aposentada.

O simulador em alemão confirmou a sidebar com os próprios olhos: três ações rápidas, um
cabeçalho lendo **"Leerzeichen"** (o caractere de espaço — "Espaços" traduzido como
tecla) e nove linhas de duas alturas antes da primeira conversa, que ficava uma tela
inteira abaixo do topo.

### O que foi entregue, PR a PR

Seis. Todos mergeados em `main`, nenhum aberto. Cada um com iOS e macOS compilando e a
suíte inteira verde antes do merge.

| PR | Lotes | O quê |
|---|---|---|
| [#38](https://github.com/JoaoZaokk/odysseus-ios/pull/38) | 01, 02, 03 | Sidebar: conversas primeiro, "Espaços" recolhível (fechado no iPhone, aberto no iPad/macOS), sem "Nova conversa" duplicado, sem "Tema", sem subtítulos, linha de chat de uma altura, busca esconde a navegação. "Leerzeichen" → "Bereiche" (nl "Spaties" → "Werkruimtes"); login em inglês em **22 idiomas, pt-BR incluído**; "Alta" sem entrada em 44; "Sprache und Modelle" → "Stimme und Modelle"; zona de perigo em português em 43 idiomas (`Text(String)`) |
| [#39](https://github.com/JoaoZaokk/odysseus-ios/pull/39) | 05, 06 | Usuários batia em `PUT/DELETE /users/{u}` (não existe; 404 atrás de "Falha") → `/admin`, `/rename`, `DELETE /users` com corpo; "Apagar TUDO" → laço pelas 8 categorias; grupo ADMIN só para admin (`AppState.isAdmin`, falha aberto); remover endpoint pergunta. Busca grava ao perder foco, clampa como a web, não posta placeholder se o load falhou, chave só quando editada |
| [#40](https://github.com/JoaoZaokk/odysseus-ios/pull/40) | 04, 12 | Fixar/desafixar e arquivar pelo swipe, "Arquivadas" atrás do cabeçalho, apagar pergunta. `ReviewGate`: pede avaliação após a 5ª resposta limpa, ≥3 conversas, ≥3 dias, uma vez por versão; 401 ou stream com erro envenena o lançamento (só em memória). Card Versão + "Avaliar o Odysseus" em Conta |
| [#41](https://github.com/JoaoZaokk/odysseus-ios/pull/41) | 07, 08, 09 | Lembretes: template do webhook (sem ele o servidor recusa entregar), teste com corpo real e erro lido do 200, persona vira menu, canal traduzido sem "none". Endpoints: resposta do POST lida (verde só se o host respondeu), chip Imagem, visível/total. Fallbacks: editor morto removido, `utility_model_fallbacks` + `vision_model_fallbacks` + `search_fallback_chain` |
| [#42](https://github.com/JoaoZaokk/odysseus-ios/pull/42) | 10, 11 | Alemão: Gedächtnis ≠ Erinnerungen, chip de status num registro só, Endpunkt, API-Schlüssel, aspas „…“, du nos alertas do sistema (de ×3 + nl), de-AT/de-CH de volta a Protokolle. 2FA de verdade em Conta (QR, código, códigos de backup, desativar por senha) |
| [#43](https://github.com/JoaoZaokk/odysseus-ios/pull/43) | — | Este handoff |

### O que ficou de fora, de propósito

Registrado no ranking do workflow e mantido aqui para não ser redescoberto:

- **Aparência com os 33 interruptores de visibilidade da web** (L). A metade que o review
  vê — a sidebar — foi resolvida mudando o **padrão**; um opt-in que ninguém descobre não
  responde "unaufgeräumt".
- **Atalhos de teclado / seção Atalhos** (M/L). Review de iPhone; nada disso é visível.
- **Privilégios por usuário** (7 toggles + limite diário + modelos permitidos). Multiusuário
  administrativo; o reviewer quase certamente roda servidor de um usuário.
- **GitHub Copilot / ChatGPT Subscription por device flow; tokens de agente via `/api/tokens`**.
  Os itens "Claude Agent"/"Codex Agent" do menu de integrações continuam produzindo 400 —
  **remover esses dois itens é a próxima coisa barata** (lote 13, não feito).
- **CalDAV/CardDAV gravados no store errado** (lote 13, M, não feito): o app manda para o
  store genérico de integrações e a conta nunca conecta, e grava a senha em texto puro.
  É o bug mais grave que sobrou aberto. `CLAUDE.md:42` ("CalDAV/CardDAV use base_url")
  é a documentação que gerou o erro.
- **Auto-resposta de e-mail, cancelamento de newsletter, estilo de escrita**. Maior lacuna
  real de Ajustes; precisa de tela nova com escopo por conta. Candidato nº 1 da 1.10.
- **Canal "browser" com notificação local.** Só escondido e explicado; push é projeto próprio.
- **Lote 14** (adições baratas: `agent_max_tool_calls`, `share_defaults_with_users`, Importar
  dados, logs com auto-refresh e 1000 linhas, Testar provedor de busca, card de geração de
  imagem do servidor) e **lote 15** (busca FTS5 no servidor + agrupamento por data) — não
  feitos, cabem na 1.10.
- **Outros idiomas**: es/fr/it traduzem "memórias" como *memoirs*; nl "Evenementen"; zh-Hans
  "代理" (proxy) para agente. Verificados, não corrigidos — cada um pede decisão de registro.
- **Apagar de-AT**: hoje é cópia de de sem nada austríaco. Decisão separada (enum, picker,
  teste, listagem na App Store).

### A resposta à review

Não foi publicada — responder na App Store é ação pública e fica com o dono. Rascunho em
alemão no fim da conversa que fechou esta rodada; o gancho é o mesmo das respostas do
OpenWebUI: agradecer, dizer o que mudou na 1.9 e onde, sem pedir nota.

### Números desta rodada

- 10 investigadores + 80 refutadores + 1 sintetizador = 91 agentes; 5 PRs de código.
- Testes: 184 → **234** (AdminRoutes 9, SearchSettings 7, ReviewGate 11, SessionArchive 7,
  SettingsWires 10, TwoFactor 6). Toda asserção que decide algo foi sabotada de propósito
  antes de ser acreditada: rota de usuário, clamp de tokens, flag de erro do stream.
- Chaves: 617 → **629** (−9 subtítulos órfãos, +21 novas: Alta, Apagado %lld/%lld,
  Arquivadas, Nenhuma conversa arquivada., Avaliar o Odysseus, Canal, Navegador, hint do
  browser, template do payload, Conectado %lld, Modelos %lld/%lld ×2, nove do 2FA).
- Alemão: 3 catálogos + 3 InfoPlist; nl InfoPlist.

## O que aconteceu nesta rodada

Doze candidatos a aprofundamento, explorados por seis agentes independentes por subsistema,
cada um entregue a um refutador adversarial cujo padrão era REFUTADO.

| | |
|---|---|
| Sobreviveram limpos | **2** |
| Sobreviveram em escopo menor | **4** |
| Mortos | **6** |

**A taxa de refutação é o dado que importa: 10 de 12.** Ela vale para a próxima rodada.

### O que foi entregue, PR a PR

Nove. Todos mergeados em `main`, nenhum aberto.

| PR | O quê |
|---|---|
| [#29](https://github.com/JoaoZaokk/odysseus-ios/pull/29) | Os dois candidatos que sobreviveram limpos — o seam de transporte e `Theme.danger` — mais os escopos que sobreviveram das dez refutações: seam de plataforma, vazamento de credencial, `ResearchRun`, `ReportBlock`, `Font.ody(design:)`, veredito de e-mail, `SettingsUI` com casa própria, clock e poll do Deep Research, pré-condição do barge-in, sessão de TTS silenciosa |
| [#30](https://github.com/JoaoZaokk/odysseus-ios/pull/30) | Três cópias de conhecimento que o enum já tinha: `lprojName` deixou de ser `String?` nunca-nil, `whisperCode` (morto em produção) foi deletado, e a tabela de 39 entradas do `AppLanguage.match` virou `AppLanguage(rawValue:)` com **teste de propriedade** no lugar de 39 conferências pontuais |
| [#31](https://github.com/JoaoZaokk/odysseus-ios/pull/31) | Uma grafia só para chave formatada: `L(_:_:)` já roda `String(format:)`, então `String(format: L("… %@"), x)` era a mesma chamada escrita duas vezes |
| [#32](https://github.com/JoaoZaokk/odysseus-ios/pull/32) | `SettingsUI.failure` — as três regras de falha ganham casa e onze testes; mais 13 sites de falha que ainda pintavam com `theme.accent` |
| [#33](https://github.com/JoaoZaokk/odysseus-ios/pull/33) | O registro de por que a recusa do helper estava errada (erro de método, não de conta) |
| [#34](https://github.com/JoaoZaokk/odysseus-ios/pull/34) | A string do barge-in traduzida em 43 idiomas, composta da irmã já revisada de cada catálogo |
| [#35](https://github.com/JoaoZaokk/odysseus-ios/pull/35) | O patch de STT do servidor marcado como não-aplicável em vez de pendente |
| [#36](https://github.com/JoaoZaokk/odysseus-ios/pull/36) | Este handoff fechado |
| [#37](https://github.com/JoaoZaokk/odysseus-ios/pull/37) | Esta tabela — o handoff citava um PR de oito |

E a issue [#20](https://github.com/JoaoZaokk/odysseus-ios/issues/20) fechada com o balanço no
topo dela: 12 corrigidas, 3 retratadas, 61 nunca verificadas.

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

10. **`ENDPOINTS.md` e `CLAUDE.md` são gitignorados** — o espelho público não os tem. Um
    commit que "corrige a documentação" neles não sobe; o `git add` avisa e continua, e a
    mensagem de commit fica mentindo. Confira `git show --stat` antes de citar o arquivo.
11. **`.ody(size:)` não tem `design:`.** `CLAUDE.md` afirmava o contrário por três rodadas.
    Monospace é `.ody(size: 12).monospaced()`.
12. **A sessão de stream também recebe `protocolClasses`.** `StubTransport.Reply.sse` funciona
    pelo `bytes(for:)` — foi assim que o sinal de "resposta limpa" do `ReviewGate` ganhou
    teste sem tocar em rede.
13. **Um `xcodebuild test` que falha em "Simulator device failed to launch" não é teste
    falhando.** Reinicie o simulador de teste e rode de novo antes de procurar bug.

## Método, se houver rodada 5

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

O que a rodada 4 acrescentou:

- **Ler o fonte do servidor antes de "portar" uma tela.** A web é open-source
  (`pewdiepie-archdaemon/odysseus`); um clone raso responde em segundos se a rota existe,
  qual é o corpo e o que volta. Três das quatro mentiras de Ajustes eram rotas inventadas
  em `ENDPOINTS.md` e "verificadas" só por leitura da própria doc.
- **Abrir o app no idioma da review antes de teorizar.** `simctl launch … -AppleLanguages
  "(de)"` custou um minuto e mostrou "Leerzeichen" — nenhum agente tinha chegado nisso pela
  leitura do catálogo, porque em alemão a palavra é uma tradução válida de "espaços".
- **Quando o achado é contrato, o refutador confirma; quando é refatoração, ele mata.**
  80/90 contra 2/12. Calibre a expectativa pelo tipo de achado, não pela rodada anterior.
