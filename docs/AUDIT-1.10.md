<!-- Gerado em 2026-09-11 pela rodada 8 (auditoria 1.10): 13 achadores + 156 refutadores (opus), servidor vivo pinado em d8a2059..28c333e, upstream HEAD 9d5c031. Os itens marcados ✅ foram implementados nesta mesma rodada. -->

# Odysseus iOS/macOS 1.10 — plano de execução
Base: 78 achados em `verdicts.json` (41 sobreviveram aos 2 refutadores). Servidor vivo = árvore d8a2059 (2026-07-23) .. 28c333e (2026-07-30); HEAD upstream = 9d5c031 (2026-09-11), 132 commits à frente. Severidade usada = a CORRIGIDA pelos refutadores.

## 1. Servidor vivo × upstream HEAD

### 1a. Quebra AGORA contra o servidor vivo (`breaks_now`)
| # | Arquivo do cliente | Commit/arquivo upstream | Mudança | Sev. corrigida |
|---|---|---|---|---|
| #12 | `Features/Notes/NotesAPI.swift:4-6` + `NotesView.swift:13-16,67` | `d8a2059:routes/note/note_routes.py:623-639` (`archived` query; 0 commits no delta) | Pedir `GET /api/notes?archived=true` quando o toggle está ligado (hoje a aba Arquivados é sempre vazia e a nota arquivada fica inacessível). | P1 |
| #13 | `Features/Brain/BrainAPI.swift:19-21` | `d8a2059:routes/memory/memory_routes.py:486-497` (`pinned: bool = Form(True)`) | Mandar form `pinned=false` em `POST /api/memory/{id}/pin` — hoje "Desafixar" é no-op silencioso. | P1 |
| #24 | `Features/Calendar/CalendarAPI.swift:32-44` + `CalendarView.swift:52-56` | `d8a2059:routes/calendar_routes.py:1511-1665` (só parse, zero `db.add`) | `quickParseEvent` deve devolver o `event` e encadear `createEvent(...)` (ou abrir o form pré-preenchido como `static/js/calendar.js:2033-2060`). | P1 (era P0) |
| #25 | `Features/Calendar/CalendarAPI.swift:25-27` | `d8a2059:routes/calendar_routes.py:1212,1221` (`scope="series"` default) | Decodificar `is_recurrence`/`series_uid` e mandar `?scope=occurrence`; hoje apagar 1 ocorrência apaga a série inteira (perda irreversível no CalDAV). | P1 |
| #26 + #61 + #62 | `Features/Email/EmailAPI.swift:55-68,82-90,149` + `EmailView.swift:45-54` | `d8a2059:routes/email_routes.py:3645-3690` (200 + `success:false`), `:5538-5545`, `:5858-5864` (`imap`/`smtp` por protocolo) | Helper `expectOK(_:)` que lê `ok`/`success`/`error` e lança; `testEmailAccount` ler `imap.error`/`smtp.error`; não remover a linha da lista antes da confirmação. | P1/P2 |
| #60 | `Models/Models.swift:64-79` + login em `APIClient` | `d8a2059:routes/auth_routes.py:148` / `HEAD:177` → `{"ok":false,"requires_totp":true}` | Aceitar `requires_totp` (única chave que o servidor manda; `totp_required`/`requires_2fa` não existem upstream) + teste de seam com `StubTransport`. | P1 (era P0) |
| #14 | `Features/Library/LibraryView.swift:44-51` (e `deletePersonal`) | `d8a2059:routes/personal_routes.py:278-346` indexa PDF+embeddings dentro do request (≤25 MB) | Enviar por `streamSession` (como `Attachments.swift:40-41`); a sessão de 30 s (`APIClient.swift:89-90`) corta o upload. `kind` corrigido de `breaks_on_head` → `breaks_now`. | P1 |
| #16 | `LibraryView.swift:44-51,77-85` | `d8a2059:routes/personal_routes.py:295-346` (`success` fixo) + `src/personal_docs.py:292-311` | Ler `indexed_count`/`failed_count` e chamar `POST /api/personal/reload` antes do `load()`. | P2 |
| #1 | `Networking/StreamEvent.swift:54,93,107-112` | `d8a2059:src/llm_core.py:2308-2315` (21 de 25 frames `error` são string) | Decodificar `error` como String **ou** objeto e aceitar `text` sem exigir `status >= 400`. | P2 (era P1) |
| #2 | `Networking/ChatStreamClient.swift:154-163` | `d8a2059:routes/chat_routes.py:611,614,621-623,710` (`{"detail":…}`) | `extractError` ler `detail` (struct, não regex) antes de devolver o corpo cru. | P2 (era P1) |
| #20 | `Networking/APIClient.swift:248-267` | `d8a2059:routes/stt_routes.py:30-55`, `tts_routes.py:36-75`, `session_routes.py`, `src/chat_helpers.py` | `detail(from:)` aceitar `detail` como dicionário (`message`/`error`). | P2 |
| #6 | `Networking/APIClient.swift:297-304` | `d8a2059:routes/auth_routes.py:168` / `HEAD:197` = `POST /api/auth/logout` | Trocar o `GET /logout` (404 nos dois estados) por `POST /api/auth/logout` e checar o status — hoje o cookie vive `TOKEN_TTL` = 7 dias. | P2 |
| #37 | `Networking/APIClient.swift:170-174` | `d8a2059:routes/chat_routes.py:1932`, `personal_routes.py:349` (Starlette `parse_qsl`) | `allowed.remove(charactersIn: "&=?#+")` — `+` chega como espaço em todo `Query(...)`. | P2 |
| #41 | `APIClient.swift:206-209` + `SettingsAPI.swift:131-137` | `d8a2059:src/chatgpt_subscription.py:298` (401 do provedor) | `send(_:treat401AsSessionExpiry:)` = false nos 3 `deviceFlow*`; hoje o 401 do provedor derruba a sessão do app. | P2 |
| #18 | `Features/Cookbook/CookbookView.swift:47-51` | `d8a2059:routes/cookbook_routes.py:1990` (regex de `repo_id`) + `routes/shell_routes.py:1322,1329,1343` | `repo_id` = nome da tarefa (`_` no lugar de espaço) e `cmd` com cada token do spec citado separadamente — 4 de 15 pacotes dão 400 hoje. | P2 |
| #19 | `CookbookView.swift:51,72-82` | `d8a2059:routes/cookbook_routes.py:2024-2048,2732,2743` (200 + `ok:false`) | Exigir `ok == true`, mostrar `error`, guardar `session_id`. | P3 (admin-only) |
| #30 | `Features/Settings/SettingsAdminSections.swift:398-404` + `SettingsIntegrationAdd.swift:146-147` | `d8a2059:routes/mcp_routes.py:275-285` / `HEAD:routes/mcp/mcp_routes.py:282-292` | Decodificar `connected`/`status`/`error`/`needs_oauth` do POST e só dizer "conectado" se `connected == true`. | P2 |
| #31 | `SettingsAdminSections.swift:587,596-601` | `d8a2059:routes/model_routes.py:2734-2741` (substitui a lista) + correção web em `04b8829` | Reler `agentTools()` antes do POST e aplicar só o diff `id -> enabled` (hoje reabilita o que `do_manage_settings` desligou). | P2 |

### 1b. Quebra quando o dono atualizar (`breaks_on_head`)
| # | Arquivo do cliente | Commit/arquivo upstream | Mudança | Sev. |
|---|---|---|---|---|
| #0 | `APIClient.swift:449` + `ChatStreamClient.swift:31` + `ChatViewModel.swift:283-288` | `c436930` (2026-08-14) → `HEAD:src/agent_runs.py:258-267`; header devolvido em `routes/chat_routes.py:2629`/`:2645`, lido em `:2655` | Capturar `X-Odysseus-Run-Id` da resposta de `/api/chat_stream` e reenviá-lo em `/api/chat/stop` — sem ele o HEAD responde `{"stopped":false}` e o run detached termina e persiste a resposta cancelada. | P1 latente |
| #14 | `LibraryView.swift` (upload/delete) | `HEAD:routes/personal_routes.py:159,341` (`_index_job_lock`) | O mesmo conserto de `streamSession` cobre a fila: no HEAD um segundo upload/delete espera o job anterior. | P1 |
| #26 | `EmailAPI.swift` (contas) | `HEAD`: `DELETE /accounts/{id}` e `POST /accounts/{id}/set-default` passam a 200 com `ok:false` | Mesmo helper `expectOK`; hoje essas duas ainda falham com status. | P2 |
| #3 (refutado→P3) | `ChatScreen.swift:123-126`, `ChatViewModel.decide:153-165` | `1b09c56..9816523` (15–19/08), `HEAD:src/tool_approvals.py:30,482-510`, `routes/chat_routes.py:1242` | Tratar 409 do cartão de aprovação expirado (TTL 10 min/restart) em vez de mostrar JSON cru em inglês. | P3 |
| #29 (refutado→P3/P4) | `EmailAPI.swift:45-53` + `EmailView.swift:39-43` | `HEAD` acrescenta `mark_seen_failed` ao `GET /api/email/read/{uid}` | Remover o `POST /api/email/mark-read` redundante (o read já marca `\Seen`) e ler `mark_seen_failed`. | P4 |

### 1c. Capacidades novas/existentes que valem adotar
| # | Arquivo do cliente | Upstream | Mudança | Sev. |
|---|---|---|---|---|
| #54 | `Features/Chat/Attachments.swift:47`, `MessageBubble.swift:43`, `ChatScreen.swift:256` | `d8a2059:routes/upload_routes.py:354-356,383-402` (`?thumb=1`, JPEG 320², cacheado; web usa em `chatRenderer.js:148`) | `attachmentURL(_:thumb:)` e `thumb: true` nas grades de 120 pt/56 pt. | P2 |
| #15 + #64 | `Features/Research/ResearchAPI.swift:15-25`, `ResearchGraph.swift:146,205-216,219-223` | `research_routes.py:599-602` (`error`, 500 chars) + `src/deep_research.py:301-353` (`round`, `total_sources`) | Declarar `error`, exibir `error ?? message` (hoje toda falha vira "no results — reformule", texto falso) e usar o `round` do servidor em vez de recontar por transição de fase. | P2 |
| #17 | `ResearchGraph.swift:251-253` | `d8a2059:routes/research/research_routes.py:289-296` (`/api/research/cancel/{id}`) e `:259-276` (`/api/research/active`) | Cancelar no servidor ao fechar o painel e reanexar o stream de job ativo (`progress` vem aninhado). | P3 |
| #76 | `ChatScreen.swift:203-209,277-294` | `d8a2059:routes/upload_routes.py:257-262` (aceita qualquer arquivo; web tem input sem `accept` e drag-and-drop) | `.fileImporter(allowedContentTypes:[.item], allowsMultipleSelection:true)` nas duas plataformas + `.dropDestination` no Mac. | P2 |
| #5 / #8 / #21 / #32 / #33 (refutados, backlog) | `StreamEvent.swift:23-26`; nenhum consumo de `/api/prefs`; `CookbookView.swift:74-82`; `SettingsModelsSections.swift:167-173`; `SettingsAdminSections.swift:165-185` | `HEAD:routes/chat_routes.py:1839-1845,2030-2060` (`endpoint_id`/`endpoint_label`); `prefs_routes.py:69-91` + `HEAD:src/foreground_model_routing.py:17-22`; `/api/cookbook/tasks/status`; `RETIRED_SETTING_KEYS`; `needs_oauth`/`auth_url` | Adotar só depois que o servidor subir (nada quebra hoje). Atenção ao #32: contra o servidor **vivo** o app **regrediu** — `default_model_fallbacks` ainda é válido em `d8a2059:src/settings.py:145` e editável pela web. | P3/P4 |

## 2. Demais melhorias sobreviventes (prioridade corrigida)

**P0 — nenhuma.** Os dois P0 originais (#24 quick-add, #60 TOTP) foram corrigidos para P1 pelos refutadores e já estão na tabela 1.

**P1**
- l10n/a11y — #66: `Features/Research/ResearchGraph.swift:239-248` (+ `:133`, `:145-149`, `DeepResearchView.swift:200`) fala inglês nos 43 idiomas; manter `label(_:)` como fase→chave, adicionar as 7 entradas nos catálogos e renderizar com `Text(LocalizedStringKey(...))`.

**P2**
- Chat — #38 + #45 (mesmo defeito, ux+perf): `Features/Chat/ChatScreen.swift:107,149-153,157-159` rola ao fim a cada token; usar `.defaultScrollAnchor(.bottom)`, remover o `onChange(of: vm.messages.last?.content)` e manter um `pinnedToBottom` com botão "ir ao fim".
- Chat — #55: `Features/Chat/ChatViewModel.swift:294-297` + `ChatScreen.swift:114` repintam a transcrição inteira por delta; coalescer em buffer com flush ~50 ms e `id` estável no `ForEach`.
- Chat/auth — #40: `App/AppState.swift:100-130` cai na tela de login sem motivo em falha de transporte; setar `loginError` no `catch` de `tryAutoLogin`/`bootstrap`.
- Chat — #42: `Features/Brain/BrainView.swift:88` usa `wand.and.sparkles` (iOS 18/macOS 15) e o botão fica invisível no piso iOS 17 → trocar por `wand.and.stars` (uma palavra).
- macOS — #47 + #73 (duplicatas, fundidas): `.refreshable` é o único recarregar em 10 telas (`CalendarView:105`, `ChatScreen:148`, `GalleryView:68`, `LibraryView:111`, `CookbookView:113`, `SessionListView:215`, `TasksView:129`, `NotesView:73`, `BrainView:93`, `EmailView:96`) e é inerte no Mac → helper `odyRefreshable(_:)` em `Config/ScreenChrome.swift` que no macOS injeta botão no header.
- macOS — #72: `Features/Calendar/CalendarView.swift:19x` e mais 3 sites só têm `.swipeActions`; espelhar em `.contextMenu` (padrão de `SessionListView.swift:147`).
- macOS — #74: `Features/Email/EmailAccountsView.swift:280-301` apresentada sem `NavigationStack` em `SettingsSections.swift:544` e no 2º call site → envolver em `NavigationStack` + `#if os(macOS) .frame(minWidth:460,minHeight:520)`.
- macOS — #75: `App/OdysseusApp.swift:12-41` é `WindowGroup` sem `.commands` (0 ocorrências no repo); `CommandGroup(replacing: .newItem)` com "Nova conversa" mata a colisão de ⌘N com "New Window".
- macOS — #76: seletor de arquivo + drag-and-drop no composer (ver 1c).
- l10n/a11y — #43: `Features/Auth/BiometricLock.swift:28` devolve o literal pt-BR "biometria/senha" → `L("biometria/senha")` + chave nos 43 catálogos.
- l10n — #67: 9 literais fora dos catálogos (6 em `UserPrivilegesSheet.swift:35-41`, admin; "Copiar código"/"Código copiado" em `SettingsModelsSections`) → acrescentar as chaves (base 818 chaves, 0 faltando no resto).
- Perf — #54: `?thumb=1` nas miniaturas (ver 1c).
- Testes — #64: primeiro teste do `ResearchRunner` com `Reply.sse` (único consumidor de SSE fora do chat).
- Testes — #60/#61/#62: travar na seam `StubTransport` o `requires_totp`, o `{"success":false}` de archive/delete e o `imap.error` do "Testar".

**P3**
- a11y — #44 (+ #69, fundido): 12 botões de toolbar icon-only sem `accessibilityLabel`/`.help` (`CalendarView:102`, `GalleryView:63`, `LibraryView`, `BrainView:88`, `SessionListView:211,213`, …) → um `Label` + `.help` no helper de `ScreenChrome.swift:44-47` resolve em um ponto.
- a11y — #70: `Config/Theme.swift:166` usa `.custom(name, fixedSize:)` → `.custom(name, size:, relativeTo: .body)`; Dynamic Type volta para quem escolhe "Anthropic Sans" (iOS-only na prática).
- Pesquisa — #17: cancelar/reanexar pesquisa (ver 1c).
- Cookbook — #19: `ok:false` do `/api/model/serve` (ver 1a).

## 3. iOS 27 × iOS 17 — o que testar em cada runtime

Piso declarado: `project.yml:4-6` (iOS 17.0 / macOS 14.0); o projeto tem **zero** `#available`/`@available` em 278 arquivos Swift (#46), então toda regressão de versão é silenciosa.

**Simulador iOS 17.x (piso)**
1. Login (com e sem "Manter conectado") e, com o servidor desligado, confirmar a mensagem de transporte na tela de login (#40).
2. Abrir **Brain** e conferir que o botão "Organizar memórias" da toolbar aparece — é o sintoma de #42; repetir após a troca para `wand.and.stars`.
3. Varrer as 12 toolbars icon-only (#44) tela por tela (Calendário, Galeria, Biblioteca, Cookbook, Notas, Tarefas, E-mail, Sessões) e screenshotar: qualquer botão em branco = símbolo acima do piso.
4. Ajustes do iOS → Tamanho do texto em AX5, com a família "Anthropic Sans" selecionada: os rótulos devem crescer (#70).
5. VoiceOver no par adjacente `gearshape` / `square.and.pencil` de `SessionListView.swift:211,213` (#44/#69): deve anunciar "Ajustes"/"Nova conversa", não o nome do símbolo.
6. Chat: streamar uma resposta longa e tentar rolar para trás durante o stream (#38/#45); parar antes do 1º token e checar o rótulo da bolha (#36).

**Simulador iOS 27 (SDK de build)**
1. O app compila com `DTSDKName = iphonesimulator27.0` e **sem** `UIDesignRequiresCompatibility` (#49) → Liquid Glass ativo: passar pelas 8 telas com `.themedNavBar` (`Config/ScreenChrome.swift:19-28`), pela sidebar (`SessionListView.swift:202-207`) e por uma amostra dos 22 `.sheet`, comparando com os screenshots do iOS 17 (contraste de barra, legibilidade de título, botões sobre vidro).
2. Confirmar que o fundo da nav bar continua visível — `toolbarBackground(_:for:)` em `ScreenChrome.swift:23` está soft-deprecado (`deprecated: 100000.0`, renomeado para `toolbarBackgroundVisibility(_:for:)`), sem mudança de comportamento esperada (#53).
3. Lembretes/tarefas em segundo plano: agendar e verificar entrega — `BGTaskScheduler.shared.submit` está `API_DEPRECATED(ios(13.0,27.0))` e o erro é engolido por `try?` (`App/TaskNotificationPoller.swift:81`, #52).
4. Verificar no bundle construído que `UIApplicationSupportsIndirectInputEvents` realmente **não** existe (os 4 `INFOPLIST_KEY_*` de `project.yml:106-109` são no-op porque o target usa `INFOPLIST_FILE` sem `GENERATE_INFOPLIST_FILE`, #50) e testar trackpad/teclado no iPad com isso em mente.
5. Rodar o mesmo roteiro 2–6 do iOS 17 e diffar os screenshots; o único aviso do app target sob o SDK 27 é `#ImplicitStrongCapture` em `ChatScreen.swift:83` (#51) — deve desaparecer após o conserto.

**macOS 14 (piso do Mac)**: as 10 telas sem recarregar (#47/#73), os 4 sites só-swipe (#72), o modal de "Adicionar conta de email" (#74), ⌘N (#75) e os 6 sheets sem tamanho (#77).

## 4. Refutados que valem registro (corrected_claim útil)
1. **#11 — senha no Keychain (P3):** `SettingsAPI.swift:94-99` (`changePassword`) descarta a resposta e não reescreve `Keychain.passwordKey`; o auto-login silencioso quebra no primeiro cold launch em que o cookie (7 dias) não serve, ou já no 2º dispositivo. Conserto de uma linha.
2. **#10 — `renamed_self` (P3):** `SettingsAdminSections.swift:347-349` joga fora `{ok, username, renamed_self}`; a aba Conta segue com o nome velho (`SettingsSections.swift:61`) e `Keychain.usernameKey` fica morto até o cookie expirar.
3. **#36 — "(sem resposta)" (P3):** `ChatViewModel.swift:236-246` não checa `Task.isCancelled` e o Stop sai do `for try await` sem lançar (`ChatStreamClient.swift:96-99`), rotulando a bolha como falha.
4. **#63 — "Email não configurado" é código morto (P3):** `/api/email/list` engole `EmailNotConfiguredError` e devolve `{"emails":[],"total":0}` sem `error` (igual em d8a2059 e HEAD), então `EmailView.swift:143-156` nunca aparece e o usuário novo vê "Caixa vazia".
5. **#49 — Liquid Glass (P4, tarefa de verificação):** nada a corrigir; é a passada visual descrita na seção 3.
6. **#53 — `toolbarBackground` (P4, dívida futura):** renomeado no SDK 27 com `deprecated: 100000.0`; trocar só quando o piso subir para iOS 18.
7. **#48 — taxa do WAV de TTS (P2/P3 hardening):** `Features/Voice/WAVStreamDecoder.swift:110` aceita qualquer `rate > 0` (até ~4,29e9) vindo da rede; `guard rate >= 8_000, rate <= 192_000` é grátis e já tem canal de UI (`chunkFailed`).
8. **#32 — cadeia de fallback (P3, regressão própria):** o app aposentou `default_model_fallbacks` cedo; no servidor vivo a chave é válida (`d8a2059:src/settings.py:145`, `routes/model_routes.py:2440-2470`) — o comentário "a key the server retired" em `SettingsModelsSections.swift:166-173` descreve o HEAD, não o servidor do dono.

## 5. Recomendação sobre atualizar o servidor (132 commits)
**Atualize — mas depois de a 1.10 estar instalada**, e nesta ordem: app primeiro, servidor depois.

Riscos documentados no conjunto de evidências:
- **Parar o chat deixa de funcionar** (#0, `c436930`): `agent_runs.stop` passa a exigir `X-Odysseus-Run-Id`; sem a 1.10 o botão Parar responde `{"stopped":false}` em silêncio, o run detached termina e grava a resposta cancelada, queimando tokens.
- **Onda de aprovação de agente de 15–19/08** (`1b09c56`, `fd50561`, `58b2a4b`, `2b72531`, `105a7c0`, `d401e80`, `9816523`): `tool_approvals` não existe em d8a2059/28c333e. Passa a haver TTL de 10 min (`src/tool_approvals.py:30`), aposentadoria do grant em qualquer mensagem normal (`routes/chat_routes.py:1242`) sem marcar `resolved` no histórico, e 403 para token delegado — cartões antigos devolvem 409 e hoje o cliente mostra JSON cru (#3, #4).
- **Biblioteca serializa indexação** (`HEAD:routes/personal_routes.py:159,341`): com o `_index_job_lock`, upload/delete entram numa fila e somam minutos ao mesmo request — a 1.10 já cobre isso mandando por `streamSession` (#14).
- **E-mail endurece**: `DELETE /accounts/{id}` e `set-default` passam a responder 200 com `ok:false`, e `GET /read/{uid}` ganha `mark_seen_failed` (#26, #29) — coberto pelo `expectOK`.
- **Roteamento de modelo muda de contrato**: `RETIRED_SETTING_KEYS` aposenta `default_model_fallbacks` (`HEAD:src/settings.py:22`, aplicado em `routes/auth_routes.py:721/755`) e a política vira per-usuário em `/api/prefs` (`foreground_fallback_enabled` / `foreground_model_fallbacks`, fail-closed, `HEAD:src/foreground_model_routing.py:17-22`) — **o app 1.10 não tem UI para a nova chave** (#8, #32): é o único item em que atualizar o servidor *perde* função. `0dd70a7` (`REQUEST_SENTINEL_OWNERS`, contrato de owner) só trocou um import nas rotas de pesquisa, sem mexer no SSE (#15).
- Capacidades que o servidor novo oferece e a 1.10 pode adotar depois, sem pressa: `endpoint_id`/`endpoint_label` em `model_info`/`model_actual`/`metrics` (#5) e `/api/cookbook/tasks/status` (#21).

O que a 1.10 já cobre ao subir o servidor: #0 (run id), #14 (fila de indexação), #26 (escritas de e-mail), #60 (`requires_totp`, idêntico nos dois estados), #1/#2/#20 (mensagens de erro, que só aumentam em volume no HEAD: 40 frames `event: error` contra 25).
Pendências a aceitar no dia da atualização: #3 (409 do cartão expirado), #29 (`mark_seen_failed`), #8/#32 (fallback per-usuário sem UI).

Observação de escopo: os commits `b4d1293` e `b19d327` (cookie `Secure`) **não aparecem em `verdicts.json`** — não há evidência no conjunto auditado para avaliá-los; precisam de uma passada própria no delta antes do update.
