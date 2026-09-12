# Handoff — fase de arquitetura, encerrada; rodadas 4 a 8 fechadas, 1.9 em revisão, 1.10 no branch

Estado em 2026-09-11. **1.9 — iOS build 25, macOS build 19** no App Store Connect
(iOS WAITING_FOR_REVIEW, macOS READY_FOR_REVIEW). **1.10 — iOS build 26, macOS build
20** no branch `feat/1.10-upstream-sync` (PR aberto): **324 testes** passando no
simulador **iOS 27** (Xcode 27) e no **iOS 17** (piso), iOS e macOS compilando sem
aviso. Catálogos: **43 × 833**.

## Rodada 8 — o servidor vivo não é o upstream

Pedido: "procura melhorias e atualizações; olha o servidor principal e o repositório
original; testa no iOS 27 e no iOS 17". Só agentes opus/sonnet (fable proibido).

**Primeiro fato, e o que muda tudo:** o servidor do dono (`odysseus.macrozao.online`,
`/api/version` = 1.0.3, público) roda a árvore upstream entre **d8a2059 (23/07) e
28c333e (30/07)** — provado por md5 dos JS estáticos (também públicos) contra
`git show <h>:static/js/<f>`. Está **132 commits atrás** do HEAD `9d5c031` (11/09). Todo
achado foi classificado em *quebra contra o vivo* × *quebra quando o dono atualizar*.
Sem esse pin, a onda de aprovações de agente de 15/08 teria virado "bug do cliente".

**Método:** 13 achadores (6 fatias do delta upstream + 7 lentes no cliente) → 78 achados
(top 6 por achador) → 2 refutadores por achado (evidência + impacto, sobrevive só se
ambos passam) → 41 sobreviventes, 37 refutados — a maioria por "verdadeiro, mas sem
efeito observável / severidade inflada". Síntese em `docs/AUDIT-1.10.md`. Cap de
concorrência do Workflow é **por workflow** (6 neste M2): a verificação foi partida em
dois workflows e correu no dobro da vazão.

### O que o 1.9 fazia errado contra o servidor VIVO (corrigido, com teste na seam)

| | Rota / contrato | Estava |
|---|---|---|
| Sair | `POST /api/auth/logout` | `GET /logout`, rota inexistente; cookie valia 7 dias depois de "Sair" |
| 2FA | login 200 `{ok:false, requires_totp:true}` | cliente só conhecia `totp_required`/`requires_2fa` — conta com TOTP entrava "logada" e caía em 401 |
| Notas | `GET /api/notes?archived=true` | aba Arquivados sempre vazia; arquivar sumia com a nota |
| Memória | `pin` com `pinned=false` em form | desafixar era no-op (servidor assume `true`) |
| Calendário | `quick-parse` só interpreta; criar é `POST /events` | o app descartava o evento e "criava" nada |
| Calendário | `DELETE …?scope=occurrence` | apagar 1 ocorrência apagava a série inteira |
| E-mail | 200 + `{success:false}` em archive/delete/accounts | linha sumia da lista, mensagem ficava no servidor |
| Cookbook | `repo_id` é id de tarefa; tokens do pip citados um a um | 4 de 15 pacotes davam 400 "Invalid pip package name" |
| Cookbook | `model/serve` 200 `{ok:false, error}` | "instalação iniciada" com tmux ausente |
| MCP | POST devolve `connected/status/error/needs_oauth` | "ok" com servidor que nunca subiu; agora a folha fica aberta com o motivo |
| Biblioteca | upload indexa dentro do request; `indexed/failed_count` | sessão de 30 s cortava PDFs; recusa lida como sucesso; lista parada sem `/reload` |
| Erros | `error` string no SSE, `detail` string/array/**dicionário** | "Erro no stream" / "Erro 503" / JSON cru na bolha |
| Query | `+` vira espaço no Starlette | `encQuery` escapa `+` |
| Device flow | 401 do provedor ChatGPT | derrubava a sessão do app inteiro |
| Pesquisa | quadro final `{error}`; `POST /research/cancel/{id}` | motivo descartado; fechar o painel não cancelava o job |
| Launch | re-login silencioso falhou | tela de login em branco, sem `loginError` |

### O que quebra quando o dono atualizar o servidor (já coberto)

`POST /api/chat/stop/{sid}` passa a exigir `X-Odysseus-Run-Id` (c436930): o cliente lê
o header da resposta do `chat_stream` (`.runStarted`) e devolve no stop; o vivo ignora.
Recomendação ao dono: atualizar o servidor (a onda de 15/08 endurece aprovações de
agente e o `Default/Local owner`; o 1.10 já entende `tool_approval`, o run id e o 503
do store de memória).

### iOS 27 × iOS 17

Xcode 27 / SDK iOS 27 compilam o projeto sem erro e com **um** aviso no app (captura
`[weak app]` redundante em `ChatScreen`, removida). Doze telas capturadas nos dois
runtimes (iPhone 17 / iOS 27 e iPhone 15 Pro / iOS 17) via bypass numa cópia da árvore:
mesmo layout; no 27 o Liquid Glass entra sozinho (voltar circular, busca da lateral no
rodapé, ícones em pílula). **Uma diferença real:** o botão "Auditar" do Brain usava
`wand.and.sparkles` (SF Symbols 6 = iOS 18) e **não existia no iOS 17**. Trocado por
`wand.and.stars` (iOS 14) e agora `scripts/check-symbols.sh` roda em todo build dos
dois alvos e **falha** se qualquer `Image(systemName:)` exigir mais que iOS 17 /
macOS 14 (lê `CoreGlyphs.bundle/name_availability.plist`; sabotado e restaurado para
provar que morde).

### macOS

⌘N virou comando de menu (`AppCommands.swift`, substitui o "New Window" automático do
`WindowGroup` que roubava o atalho); View › Atualizar / ⌘R dispara `.odyRefreshable`
nas 10 telas que só tinham pull-to-refresh; ações destrutivas ganharam `.contextMenu`
(Brain, Calendário, E-mail, Contas, Biblioteca); "Nova conta" de e-mail aberta de
Ajustes ganhou cabeçalho com Cancelar e tamanho (`standalone: true`).

### Refutados que valem registro

Senha trocada não atualiza o Keychain (#11) e renomear a própria conta deixa
`username` obsoleto (#10) — verdadeiros, ficaram fora por impacto; cartão de aprovação
expirado (409, só no HEAD, #3); Liquid Glass "ligado" (#49) é o comportamento esperado
do SDK 27, não bug; `toolbarBackground` (#53) não tem aviso hoje. Lista completa em
`docs/AUDIT-1.10.md › 4`.

### Chaves novas (13 × 43)

Calendário (3), MCP (3), fallback genérico "O servidor recusou a operação.", Biblioteca
(1), pesquisa (4: sem resultados, rodada, linha de status, "aviso"), `biometria/senha`.
Sempre por script com assert de ausência + `plutil -lint` — `add_keys_110.py` é o molde.

## Rodada 7 — a Rückfrage que não aparecia

Review alemã de 8/9 (4★, "Guter Start"): *"Nach ein paar Stunden testen ist mir
aufgefallen, dass die **Rückfragen** im Chat nicht angezeigt werden."*

Não era mensagem sumindo. Testado no simulador contra o servidor real: conversa nova,
resposta, pergunta de seguimento — tudo aparece, e o histórico volta inteiro. O que
sumia era a pergunta **do agente**.

O servidor tem a ferramenta `ask_user` (`src/agent_tools/interaction_tools.py`): o
agente faz uma pergunta de múltipla escolha, o loop emite
`data: {"type":"ask_user","data":{…}}` e **encerra o turno** — a resposta do usuário
chega como a próxima mensagem. O mesmo evento carrega o **pedido de aprovação de
ferramenta** (`kind: "tool_approval"` + `approval_id`, de `src/tool_approvals.py`), que
espera uma decisão pelo canal de controle. O `ChatStreamClient` não conhecia nenhum dos
dois: os quadros caíam no `default` do `switch` e o turno terminava sem texto — bolha
vazia, ou `_(sem resposta)_`. Vale para o modo Agente **e** para o chat comum, porque o
servidor promove `chat → agent` sozinho por intenção (`_classify_tool_intent`), então
quem nunca tocou no chip Agente também batia nisso.

| Peça | O que passou a existir |
|---|---|
| `AskUser` (em `Networking/StreamEvent.swift`) | Decodifica o payload: `question`, `options[{label, description, value}]`, `multi`, `kind`, `approval_id`, `action`, `resolved`. `isRenderable` derruba cartão malformado (< 2 opções) e cartão já resolvido, como a web. |
| `AskUserCard` (`Features/Chat/AskUserCard.swift`) | O cartão: pergunta, opções com descrição, seleção múltipla com caixas, campo "Outra resposta…". Na aprovação mostra a ação exata (ferramenta, comando, efeitos) em monoespaçada e **sem** campo livre — resposta digitada não é autorização. |
| `ChatViewModel.pendingAsk` | Sobrevive ao fim do stream, como os `notices`. Escolher manda o rótulo como próxima mensagem (é o que o servidor espera); digitar qualquer coisa também fecha o cartão. |
| `ChatViewModel.decide` | Aprovação vai por `tool_approval_id` + `tool_approval_decision` num turno **sem mensagem** (`routes/chat_routes.py` aceita corpo vazio quando há approval). Recusa devolve só `tool_approval_resolved`, que virou o aviso "Você recusou a ação, e o agente parou aqui." |
| `Message.askUser` | Lê `metadata.tool_events[].ask_user` do histórico: reabrir a conversa traz o cartão de volta se ele ainda for o fim do fio. |
| Bolha vazia | Um turno que termina em pergunta (ou em recusa) não vira mais `_(sem resposta)_` — a bolha placeholder é removida. |

17 testes novos (`OdysseusTests/AskUserTests.swift`), com os quadros copiados dos
`json.dumps` do servidor. Duas chaves novas nos 43 catálogos ("Outra resposta…" e o
aviso de recusa); o botão fechar e o de enviar reaproveitam "Fechar" e "Enviar
mensagem", que já existiam. Verificado na tela em pt-BR e em alemão.

### Publicação da 1.9 (10/09)

Subida pelas duas plataformas com `xcodebuild archive` → `-exportArchive`
(`method: app-store-connect`, assinatura automática, team FZ5A72S5DT) →
`xcrun altool --upload-app`, com a chave de API do App Store Connect que já vive na
máquina do dono (o caminho e o issuer estão no `CLAUDE.md` local, que é gitignored).
iOS sai `.ipa` (`-t ios`), macOS sai
`.pkg` (`-t macos`); as duas validaram e subiram sem erro e ficaram **VALID**.

O macOS é build nativo, não port do iOS: alvo `Odysseus-macOS` (`platform: macOS`),
`LC_BUILD_VERSION platform MACOS`, universal `x86_64 + arm64`, bundle `Contents/MacOS`,
sandbox. Fonte SwiftUI compartilhada com **49 blocos `#if os(macOS)` em 25 arquivos**,
mais `PlatformCompat.swift` e `ScreenChrome.swift`, que só existem para o Mac.

**Pular 1.7 → 1.9 no Mac é permitido**: a Apple exige versão maior que a última
publicada naquela plataforma, não sequência.

| O que estava faltando | Fechado |
|---|---|
| Não existia registro de versão 1.9 no ASC | Criados os dois (`MANUAL`), build anexado em cada |
| es-MX e pt-PT sem capturas (desde a 1.7, caíam no fallback do idioma principal, que é pt-BR — o mexicano via a ficha com print em português) | es-MX copiou de es-ES, pt-PT de pt-BR: 5 iPhone 6,7" + 5 iPad 12,9" cada |
| `ipad_4_4-themes.png` duplicada em `cs` desde a 1.8 | Removida |
| `promotionalText` **vazio nas 55 localizações** (30 iOS + 25 macOS) | Preenchido em todas, ≤170 chars |
| O 4º item das novidades citava "GitHub Copilot e assinatura do ChatGPT" em 52 locales | Trocado pela frase neutra que o chinês já usava. **A descrição aprovada da 1.8 não nomeia serviço de IA de terceiros em locale nenhum — a regra vale para a ficha inteira, não só para a China.** |
| Notas de revisão do Mac: em português, bloco "preencha a URL" repetido 3× e o passo 1 dizendo o CONTRÁRIO ("já vem preenchido"), além de afirmar transcrição 100% no aparelho, que a 1.8 deixou de ser verdade absoluta | Reescritas em inglês espelhando as do iOS; a repetição do aviso ficou de propósito (3× no topo, 1× no HOW TO TEST) e o iOS ganhou a mesma repetição. Bloco de credenciais copiado byte a byte do texto antigo |

Varredura final das 55 localizações: **zero campo obrigatório vazio**, **zero menção a
OpenAI/ChatGPT/GPT/Copilot/Whisper** em nome, subtítulo, descrição, palavras-chave,
promocional, novidades ou URLs. O chinês já estava limpo antes — o problema estava nos
outros.

O Mac tem **25 locales** contra 30 do iPhone (faltam fr-FR, fi, he, sv, th). Vem de
antes da 1.9; não foi mexido.

### Versão pt-PT do app: decidido não fazer

Zero avaliações de Portugal (as duas do app são alemãs) e a chave de API é *App Manager*,
que leva 403 no endpoint de analytics — não dá para ler download por território por
script. Contra isso, o custo é um 44º catálogo de 820 chaves e toda rodada futura
traduzindo ×44 para sempre, em troca de uma dúzia de palavras (Ajustes/Definições,
tela/ecrã, usuário/utilizador). A ficha pt-PT da loja já existe e o texto que escrevi
está em português europeu. Revisitar só se o Analytics mostrar instalação real lá.

## Rodada 6 — "feche esses cinco"

As cinco decisões que a rodada 5 tomou sem perguntar (abaixo, em "Decisões tomadas sem
perguntar") deixaram de ser decisões e viraram código, num PR só
([#45](https://github.com/JoaoZaokk/odysseus-ios/pull/45)). Nada ficou "fechado por
decisão" desta vez.

| Decisão da rodada 5 | Fechamento |
|---|---|
| **Aparência: os 33 interruptores da web "não existem no app nativo"** | Existem os que têm superfície nativa. `UIVisibility` (um `UserDefaults`, `ui.hidden`, conjunto de ids escondidos — o espelho do `odysseus-ui-visibility` do localStorage da web) e a folha **Aparência › Personalizar interface**: barra lateral (Deep Search, "Espaços" como chave-mestra, os nove espaços), campo de mensagem (Web, Deep, Agente, Anexar fotos, Microfone) e conversa (raciocínio, nome do modelo, boas-vindas, largura total — desligada vira coluna de leitura de 720 pt no iPad/Mac). "Restaurar padrão" por cartão. O que a web tem e o app não (rail, incógnito, RAG, presets, emojis) não ganhou interruptor: não há o que esconder. |
| **Tokens de agente só com escopo `chat`; "editar escopos fica na web"** | Ao criar Claude/Codex Agent o formulário mostra os escopos do servidor (`/api/tokens/profiles`, fallback na lista fixa) com `chat` pré-marcado. Em Tokens de API cada linha ganhou **Editar**: nome e escopos por `PATCH /api/tokens/{id}` (JSON). Só o que mudou vai no corpo — um rename sem a chave `scopes`, que é a regressão que o próprio servidor testa (mandar `scopes` num rename resetava para `chat`); nada mudou, nada é enviado. |
| **Notificações opt-in, só com o app aberto** | Continua opt-in (isso era a parte certa). O que mudou: `TaskNotificationPoller.refreshOnce()` é a única leitura da fila, compartilhada pelo laço de 30 s e pelo **background refresh do iOS** (`BGAppRefreshTask`, id `com.zao.odysseus.tasks.refresh`, `UIBackgroundModes: fetch`; pedido a cada ida ao fundo e depois de cada refresh; o sistema decide quando, nunca antes de 15 min). No **macOS o laço não para mais ao trocar de app**: o `scenePhase` só manda no iOS; no Mac o poller vive com a sessão. O texto de Conta diz cada coisa em cada plataforma. |
| **Sem APNs** | Fechado de vez: o servidor não tem push, e o cliente agora faz o máximo que um cliente faz sozinho (acima). Não é pendência; é limite do servidor. |
| **de-AT fica** | Saiu. Era cópia byte a byte de `de` com um item duplicado no seletor; iOS resolve "Deutsch (Österreich)" para `de` (`AppLanguage.match("de-AT") == .de`, testado). de-CH fica — suíço é real (sem ß). Catálogos: 43. |

Chaves novas: **26**, traduzidas por workflow (tradutor + revisor por grupo, todos Opus,
lendo o catálogo-irmão antes de escrever), verificadas por script (`%@`, vazio,
não-traduzido); duas chaves órfãs removidas dos 43 (o texto antigo do agente e o antigo
aviso de Conta). Testes novos em `ClosingItemsTests` (13): visibilidade pura, escopos
no form, PATCH parcial, `refreshOnce` desligado/sem permissão.

Nada ficou aberto desta rodada. As duas ações do dono continuam as mesmas: subir a 1.9
(build 24) e responder a review alemã depois que a 1.9 estiver no ar.

## Rodada 5 — "resolva os abertos, todos eles, uma tacada só"

Tudo que a rodada 4 tinha deixado de fora, fechado num PR (#44). Método: um workflow de
oito leitores (Opus) extraiu o contrato exato de cada rota no fonte do servidor e o ponto
de inserção no app; depois implementação sequencial, testes pelo `StubTransport`, build
dos dois alvos, e um workflow de tradutores + revisores por grupo de idiomas para as
chaves novas.

### O que entrou

| Item | O quê |
|---|---|
| Lote 13 | CalDAV vai para `/api/calendar/config/accounts` **depois de um PROPFIND real** (`/api/calendar/test`); CardDAV é uma conta global em `PUT /api/contacts/config` com chaves `carddav_*`; "Claude/Codex Agent" viram **tokens de API** (form em `/api/tokens`, revelados uma vez); API Service ganha presets, Basic auth, edição (PUT sem reenviar a chave mascarada) e confirmação de remoção; o teste lê `{ok,message}` do 200; a lista funde os quatro stores |
| Tokens | Seção **Tokens de API** (ADMIN): lista, criar com escopos do servidor, revelar uma vez, revogar |
| Privilégios | Folha por usuário: 7 recursos, limite diário, modelos permitidos (todos / nenhum / lista); um `PUT` com as 11 chaves; eco autoritativo |
| Device flow | GitHub Copilot e ChatGPT Subscription em **Adicionar modelos**: código + link, poll no intervalo do servidor, conectado = linha de endpoint pelo host, desconectar = `DELETE` |
| E-mail | **Automação de email** por conta: resposta automática (cooldown `period/1d/3d/7d`), limpeza de newsletters (scan → descadastrar → spam/excluir), estilo de escrita com extração dos enviados; "Enviar de" nos lembretes |
| Lote 14 | `agent_max_tool_calls` (0…1000), `share_defaults_with_users`, **Importar dados** (com confirmação; `ok:false` no 200 é falha), logs com DEBUG, 1000 linhas e atualização automática de 3 s, **Testar** provedor de busca, card de **geração de imagem no servidor** |
| Sidebar | Grupos por data (Favoritos, Hoje, Ontem, dia da semana, "N dias atrás"…) recolhíveis; busca **no conteúdo das mensagens** (FTS5, `/api/search`); indicador de resposta em andamento na linha |
| Notificações | O canal "browser" do servidor vira notificação local, **opt-in em Conta** (poll de 30 s com o app aberto; a leitura drena a fila) |
| macOS | Atalhos fixos (⌘N, ⌘F, ⌘,, ⇧⌘D, ⌥⌘↑/↓, ⌥⌘S, ⌘/, ⌘↩, ⌘. / Esc) e seção **Atalhos** somente-leitura |
| Privacidade | **Borrar dados sensíveis** (regexes do `censor.js` da web) nas respostas, opt-in em Conta |
| i18n | es/fr/it "memórias" (memoirs) → recuerdos/souvenirs/ricordi; nl geheugen ≠ herinneringen; zh 代理 → 智能体/智能體 (zh-Hant e zh-HK estavam errados nas 13 strings) |

### Decisões tomadas sem perguntar (registradas aqui para poder ser desfeitas)

- **Notificações são opt-in.** O primeiro build pedia permissão no primeiro lançamento —
  exatamente o que a App Review e o usuário detestam. Toggle em Conta, padrão desligado.
- **CardDAV** é uma conta só; o item do menu diz que salvar substitui a atual.
- **Integrações** continua visível para todo mundo, mas só CalDAV (rota por usuário) aparece
  para não-admin; API/CardDAV/tokens são rotas admin e ficam atrás de `AppState.isAdmin`.
- **Tokens de agente**: criar com escopo `chat`, revelar, revogar. Editar escopos fica na web.
- **de-AT** fica. Hoje é cópia de `de`; o custo é zero porque os scripts editam os 44 de uma vez.
- **Aparência com os 33 interruptores da web**: não existe no app nativo — a metade que o
  review via (sidebar) foi resolvida pelo padrão; o resto é cromo do DOM da web. Fechado por
  decisão, não por código.
- **Push de verdade** (APNs) continua fora: o servidor não tem.

### Chaves novas

165 chaves novas em 44 catálogos, traduzidas por um workflow (tradutor + revisor por
grupo de idiomas, com amostras do próprio catálogo para registro e terminologia) e
verificadas por script: mesmo `%@`/`%lld`/`%d` da chave, nenhuma vazia. `bo` (tibetano)
segue marcado para revisão nativa, como sempre.


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

### O que ficou de fora na rodada 4 (tudo fechado na rodada 5, acima)

Mantido como registro do ranking da época:

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
