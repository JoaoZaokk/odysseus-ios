# Auditoria do fonte 1.6 — backlog da 1.7

Gerada 2026-07-16 por workflow multi-agente (8 revisores por dimensão + 2 lentes
adversariais por achado; só entram aqui os confirmados pelas DUAS lentes).
Nada disto afeta a 1.6 em revisão — são bugs que já existiam.

## GRAVES (3)

### Odysseus/Features/Calendar/CalendarView.swift:60
**Event-creation date formatter uses device calendar — corrupts dtstart/dtend written to the server**

create() builds EventPayload.dtstart/dtend with `DateFormatter()` that has no locale set, so it inherits the device locale's default calendar and numbering. Verified with ICU: a device with region Thailand (th_TH, Buddhist calendar — the OS default there, and th is a shipped localization) formats today as "2569-07-16"; fa_IR yields Persian digits "۱۴۰۵-۰۴-۲۵"; ar_SA yields "١٤٤٨-٠٢-٠٢". That string is POSTed to /api/calendar/events and persisted into the user's real CalDAV calendar — the event lands centuries off (or unparseable), on every device synced to that calendar. A user-forced 12/24-hour override can likewise rewrite the 'HH:mm:ss' pattern (QA1480), producing "...T02:30:00 PM"-style payloads for any locale.

**Fix:** Set `f.locale = Locale(identifier: "en_US_POSIX")` on this formatter (forces Gregorian calendar, ASCII digits, literal HH).

### Odysseus/Features/Settings/SettingsSections.swift:325
**"Testar conexão" always reports "Conexão OK" in both Settings email-add flows (onTest never passed)**

AddEmailAccountView's onTest parameter defaults to `{ _ in nil }`, and nil is interpreted as success (`testResult = .ok`). The two Settings call sites use the trailing-closure form that only supplies onSave: SettingsSections.swift:325 (Ajustes > Email > Adicionar conta) and SettingsAdminSections.swift:866 (Ajustes > Integrações > Email (IMAP/SMTP)). Failure scenario: user opens either Settings flow, types a wrong IMAP password or host, taps "Testar conexão" — the app shows green "Conexão OK" without any network request, the user saves a broken account and the inbox later fails. Only the flow reached from the Email screen (EmailAccountsView.swift:97/106) wires the real test.

**Fix:** Pass `onTest: { await vm.test($0) }` at both Settings call sites (SettingsSections.swift:325 and SettingsAdminSections.swift:866).

### Odysseus/Features/Settings/SettingsAdminSections.swift:885
**"Exportar dados" backup is a silent no-op on iOS but reports "Backup exportado."**

SettingsUI.saveJSON's non-macOS branch writes the export to FileManager.default.temporaryDirectory (inaccessible to the user, no share sheet) and returns; SistemaVM.export() (line 513-520) then unconditionally sets note = "Backup exportado.". Failure scenario: on iPhone, admin taps Sistema > Exportar dados, sees the success message, believes a backup exists — no retrievable file was produced; if they later wipe a category trusting that backup, data is lost. The macOS branch also uses `try? data.write(...)` so a failed write (disk/permission) still reports success.

**Fix:** On iOS present a ShareLink/UIActivityViewController (or fileExporter) with the data, and propagate write errors so export() only reports success when a file was actually delivered.

## Moderados (confirmados) (31)

### Odysseus/Networking/APIClient.swift:156
**send() collapses every 403 into .notAuthenticated, showing 'Sessão expirada' for permission-denied and making a dedicated 403 handler dead code**

send() throws APIError.notAuthenticated for both 401 and 403. A 403 is permission-denied, not an expired session: the server answers 403 to non-admins on /api/model-endpoints/{id}/models?refresh=true (the code's own comment in SettingsAPI.swift:29 says so). Concrete failure: a non-admin user taps the model-refresh button; SettingsModelsSections.swift:37 has `catch APIError.http(403, _)` with the correct message 'Só um administrador pode atualizar a lista de modelos.' — but that clause can never match because send() already converted the 403 into .notAuthenticated, so the user instead sees the misleading 'Sessão expirada. Faça login novamente.' and may pointlessly log out/in. Every other admin-only endpoint hit by a non-admin (wipe, users, signup-toggle) shows the same wrong message.

**Fix:** Map only 401 to .notAuthenticated and let 403 flow through as APIError.http(403, detail) so callers can distinguish permission-denied.

### Odysseus/Features/Settings/SettingsAdminSections.swift:121
**exportData() rides the default session whose 30s resource cap kills the full-backup download mid-transfer**

exportData() uses send(request("/api/export")) on the default session, which has timeoutIntervalForResource = 30 (APIClient.swift:51) — a hard 30s wall-clock cap on the WHOLE transfer even while bytes are actively flowing. /api/export is the full-data backup saved as odysseus-backup.json (SettingsAdminSections.swift:516-517). Failure: a backup of a few MB (chats + memory + gallery metadata) on a slow cellular/VPN link takes >30s → the transfer is killed at exactly 30s and the user sees 'Falha ao exportar: …tempo limite' every time, with no way to complete a backup. This is precisely the case the streamSession split exists for (uploads already use it, Attachments.swift:41).

**Fix:** Route the export through the long-transfer session: try await send(request("/api/export"), via: streamSession).

### Odysseus/Features/Library/LibraryView.swift:50
**uploadPersonal() uses the default 30s-capped session while the equivalent chat upload was already moved to streamSession**

uploadPersonal() posts arbitrary user documents to /api/personal/upload via plain send(req) — the default session with timeoutIntervalForResource = 30. Failure: uploading a document larger than ~what a slow uplink pushes in 30s (e.g. a 20 MB PDF on 5 Mbps up ≈ 32s) is aborted at 30s wall clock and the Library upload fails with a timeout, reproducibly. The sibling chat-attachment upload (Odysseus/Features/Chat/Attachments.swift:40-41) was explicitly switched to streamSession with the comment 'a large photo on a slow link can exceed the 30s resource cap' — the Library path was missed.

**Fix:** Change to _ = try await send(req, via: streamSession) like Attachments.upload.

### Odysseus/Features/Library/LibraryView.swift:53
**deletePersonal() encodes the filepath with .urlQueryAllowed, leaving & = + raw, so files with those characters can't be deleted**

deletePersonal() builds ?filepath=… with addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed). That set keeps '&', '=' and '+' unescaped (they are legal query characters). Failure: the user uploads 'relatório&final.pdf' and swipes to delete → the request is DELETE /api/personal/file?filepath=relatório&final.pdf → FastAPI/Starlette parses filepath as 'relatório' and 'final.pdf' as a separate parameter → 404/no-op, the file can never be deleted from the app. A '+' in the name is decoded server-side as a space (parse_qsl), same outcome. The codebase already has encQuery() (APIClient.swift:137) built for exactly this, unused here.

**Fix:** Use encQuery(filepath) (and also strip/encode '+') instead of raw .urlQueryAllowed.

### Odysseus/Networking/ChatStreamClient.swift:130
**extractError() returns the whole regex match, so users see the raw JSON fragment '"message": "…"' as the error text**

String.range(of:options:.regularExpression) returns the range of the ENTIRE match — capture groups are inaccessible. So for a failed chat_stream start with body {"message":"Modelo indisponível"}, extractError returns the literal string '"message":"Modelo indisponível"' (including the JSON key and quotes), which is thrown as APIError.http and rendered verbatim in the chat error UI. The no-match fallback (body.count < 200 → return body) similarly surfaces the raw JSON body, e.g. '{"detail":"..."}', instead of the message. Every stream-start failure with a JSON body shows garbled text.

**Fix:** Use NSRegularExpression and return capture group 1's substring (and parse a {detail:…} body via the existing APIClient.detail helper for the fallback).

### Odysseus/Features/Calendar/CalendarAPI.swift:9
**events() query-range formatter uses device calendar — calendar shows empty for non-Gregorian-calendar regions**

The start/end query params for GET /api/calendar/events are formatted with `DateFormatter(); f.dateFormat = "yyyy-MM-dd"` and no locale. On a device whose region defaults to a non-Gregorian calendar (Thailand/Buddhist, Iran/Persian, Saudi Arabia/Islamic — all locales the app localizes into), the params become e.g. start=2569-07-16 or Persian-digit strings, the FastAPI range query matches nothing (or 422s), and the Calendar tab renders permanently empty for those users by default — no override needed.

**Fix:** Set `f.locale = Locale(identifier: "en_US_POSIX")` on the query formatter.

### Odysseus/Features/Calendar/CalendarModels.swift:73
**All-day date parse fallback uses device calendar — all-day events land in year 1483 and vanish**

CalendarEvent.parse's third branch (all-day "2026-06-25") uses a `DateFormatter` without the en_US_POSIX locale the first branch correctly sets. Verified: with a Buddhist-calendar device (th_TH) `date(from: "2026-06-25")` returns 1483-06-25 CE (year interpreted as BE); islamic-umalqura gives 2587 CE. startDate/dayKey then bucket the event centuries away from the displayed agenda range, so all-day events silently disappear (and sort wrongly) on those devices even after the query bug is fixed.

**Fix:** Set `f.locale = Locale(identifier: "en_US_POSIX")` on the all-day fallback formatter (mirroring line 66).

### Odysseus/Networking/APIClient.swift:265
**sessions() swallows decode failures and returns [] — session list silently disappears**

Both decode attempts (bare array, {sessions:[...]} wrapper) use try?; any other wrapper key, a server-update shape change, or the poisoned-array case above falls through to `return []`. SessionStore.load() then sets sessions = [] and error = nil, so the user sees the "no conversations" empty state with zero indication anything failed — perceived total data loss where every other endpoint surfaces APIError.decoding.

**Fix:** Throw APIError.decoding when neither decode succeeds on non-empty data instead of returning [].

### Odysseus/Features/Chat/ChatViewModel.swift:74
**History load/reload unconditionally replaces messages, orphaning the in-flight stream placeholder**

runHistoryLoad does `self.messages = detail.messages` with no guard against an active stream. Scenario A: open an existing chat on a slow link, type and send before GET /api/history returns (composer is never disabled while isLoadingHistory). The history response then replaces the array, deleting the just-appended user bubble and the assistant placeholder; every subsequent textDelta hits index(of:assistantID) == nil and is silently dropped, so the reply streams invisibly and the user's own message vanishes from the transcript (likely re-send → duplicate). Scenario B: pull-to-refresh (ChatScreen.swift:111 `.refreshable` is active during streaming) mid-reply wipes the placeholder the same way and the rest of the reply is lost from the UI until a later manual reload.

**Fix:** Skip/queue history application while isStreaming (or merge by id instead of assigning), and disable send()/refreshable while a history load is in flight.

### Odysseus/Features/Chat/ChatViewModel.swift:11
**@Published error is set in three failure paths but never rendered anywhere — silent failures**

ChatScreen only displays voice.error; vm.error has no consumer (grep confirms no other view holds this VM). Consequences: (1) history load failure (line 79) shows the empty-chat welcome screen — the conversation looks wiped with no explanation; (2) attachment upload failure (line 111) — user picks a photo, the spinner ends, no thumbnail appears, zero feedback; (3) stream transport error after partial text (line 204) — the reply just stops mid-sentence and the user assumes it finished.

**Fix:** Render vm.error in ChatScreen (banner near the composer, like voice.error) or route it into a ChatNotice-style inline row.

### Odysseus/Features/Chat/ChatViewModel.swift:141
**Server error frame mid-stream replaces already-streamed reply text**

`case .error(let msg): setAssistant(assistantID, content: msg)` overwrites content. If the server streams part of a reply and then emits an error frame (model crash, backend restart), the partial text the user was reading is replaced by the bare error string — inconsistent with handleStreamError (line 201), which deliberately preserves non-empty content. The visible partial reply is lost until a history reload, and the error isn't even prefixed with the ⚠️ marker used by the other path.

**Fix:** Mirror handleStreamError: append/flag the error when content is non-empty instead of replacing it.

### Odysseus/Features/Chat/ChatScreen.swift:229
**macOS ⌘V paste monitor is app-global per ChatScreen — wrong-pane or duplicate attachment with multiple panes**

Each ChatScreen installs an NSEvent local monitor that matches every ⌘V in the app, keyed only on clipboard contents — never on which pane/field has focus. The macOS workspace (WorkspaceView HSplitView) can show several ChatScreens at once: with chats A and B open and the composer of B focused, pasting a screenshot is consumed by whichever monitor runs first (installation order), attaching the image to chat A — or to both chats if AppKit dispatches to all monitors. It also hijacks image-only pastes aimed at a non-chat pane (e.g. a Notes editor next to a chat) since the guard only checks the pasteboard, not the first responder.

**Fix:** Guard the monitor on the screen's own focus (e.g. only act when inputFocused/this pane's window is key and first responder belongs to it), or install a single app-level monitor that targets the focused chat.

### Odysseus/Features/Chat/ChatScreen.swift:44
**iOS chat title rendered verbatim — 'Nova conversa' shows in Portuguese for all 43 non-pt localizations**

ChatViewModel.title is a String set to the hardcoded literal "Nova conversa" (ChatViewModel.swift:42/165). On iOS it is rendered via `Text(vm.title)` (line 44) and `.navigationTitle(vm.title)` (line 39) — the StringProtocol overloads, which do NOT consult the catalog even though every one of the 44 catalogs carries "Nova conversa" = translated. On macOS the same title goes through `Text(LocalizedStringKey(title))` in ScreenChromeContainer and IS translated, proving the intent. An English/Japanese/Arabic user opening a new chat on iPhone sees a Portuguese nav title. Same class: ensureSession's image-only fallback names the session "Imagem" (ChatViewModel.swift:120) regardless of language.

**Fix:** Localize before storing (String(localized:)) for the 'Nova conversa'/'Imagem' fallbacks, or render known-key titles via LocalizedStringKey on iOS like macOS does.

### Odysseus/Features/Research/DeepResearchView.swift:149
**Format, Search engine, Endpoint and Model pickers are dead — never sent to the API**

The settings grid exposes Format (Resumo/Detalhado/Tabela/Bullet points), Search (SearXNG/DuckDuckGo/Brave/Tavily), Endpoint and Model pickers (vm.format, vm.searchEngine, vm.endpointId, vm.model at lines 8-11), but start() only calls runner.start(api:query:maxRounds:category:) and startResearch() only serializes query/max_rounds/category (ResearchAPI.swift:67-76). A user who picks 'Tabela' + 'Brave' + a specific endpoint/model gets a run with the server defaults; all four selections are silently ignored, and the endpoint list is even fetched from the network (vm.load) just to feed a no-op menu.

**Fix:** Pass format/search_engine/endpoint_id/model in the /api/research/start body (per the web composer contract) or remove the controls until wired.

### Odysseus/Features/Gallery/GalleryView.swift:148
**Gallery videos get a play badge but cannot be played anywhere**

GalleryImage.isVideo (GalleryModels.swift:33) drives a play.circle.fill overlay on the tile (GalleryView.swift:109), implying the item is playable, but both the tile (line 96) and GalleryDetail (line 148) render via AsyncImage, which cannot decode mp4/mov/webm. A user with a generated/uploaded video sees a gray failure placeholder behind a play icon, taps it, and the detail sheet shows only the failure photo icon — the video is unviewable in the entire app. No AVKit/VideoPlayer usage exists anywhere in the target.

**Fix:** Render isVideo items with AVKit's VideoPlayer(player: AVPlayer(url:)) in GalleryDetail (and a thumbnail via AVAssetImageGenerator or server thumb).

### Odysseus/Features/Gallery/GalleryView.swift:176
**Favorite toggle in the gallery detail sheet never updates its own heart icon**

sheet(item: $selected) hands GalleryDetail an immutable copy of the image (line 69-73). Tapping the heart calls vm.toggleFavorite(img), which flips vm.images[i].favorite, but neither `selected` nor the sheet's `image` copy is updated, so the toolbar icon at line 176 keeps showing the stale state while the sheet is open. The user sees no feedback, plausibly taps again, and the second POST flips the favorite back server-side — net result: the action appears broken and can silently undo itself.

**Fix:** Have toggleFavorite also update `selected` (or pass the VM + image id into GalleryDetail and read the live value).

### Odysseus/Features/Sessions/SessionListView.swift:73
**Load/CRUD errors are never surfaced — failures masquerade as empty states**

SessionStore.error, GalleryViewModel.error, LibraryViewModel.error and CompareViewModel.error are all populated on failure but no view renders them (grep confirms zero reads). If GET /api/sessions fails (expired cookie, server down), sessions stays [] and the sidebar shows 'Nenhuma conversa ainda.' as if the account were empty; Gallery shows 'Galeria vazia' and Library 'Biblioteca vazia' on the same failure. Worse, a failed swipe-delete or rename sets store.error and does nothing visible — the row just stays, with zero feedback. Compare's model menus stay empty with no explanation when /api/models fails.

**Fix:** Render the error (banner/alert) in each view and gate the empty-state text on error == nil.

### Odysseus/Features/Settings/SettingsIntegrationAdd.swift:67
**Claude/Codex "Criar token" discards the token the server returns, making the created integration unusable**

ENDPOINTS.md documents that POST /api/auth/integrations with type claude|codex returns a token, and the sheet's confirm button is even labeled "Criar token". But createIntegration goes through postJSON (SettingsAdminSections.swift:125) which discards the response body, the sheet dismisses immediately on success, and the declared `@Published var createdToken` (line 46) is never assigned or rendered. Failure scenario: user creates a Claude Agent integration from the app, is never shown the one-time token, and cannot configure the agent — must redo it in the web UI.

**Fix:** Return/decode the creation response, set createdToken, and show a copyable token screen before dismissing (delete the dead property otherwise).

### Odysseus/Features/Settings/SettingsSections.swift:324
**AddEmailAccountView presented without NavigationStack in Settings sheets — no title and no Cancel button**

AddEmailAccountView deliberately has no own NavigationStack (its comment says the caller provides one), and its Cancelar button lives in `.toolbar`. EmailAccountsView wraps it correctly, but SettingsSections.swift:324 (`.sheet { AddEmailAccountView { … } }`) and SettingsAdminSections.swift:865 present it bare. Failure scenario: opening "Adicionar conta" from Ajustes > Email (or Integrações) shows a sheet with no navigation bar — no "Nova conta" title and no Cancelar; on iOS the user must know to swipe-dismiss, and on macOS (Settings drawer) there is no cancel control at all — the only way out is filling the required fields and pressing Criar.

**Fix:** Wrap both sheet contents in NavigationStack { AddEmailAccountView(...) } like EmailAccountsView does.

### Odysseus/Features/Settings/SettingsAdminSections.swift:244
**Admin settings VMs silently default all fields when load fails; a subsequent Save overwrites the server config with zeros/blanks**

AgentToolsVM.load() uses `(try? await api.getSettings()) ?? SettingsBag(dict: [:])` with no error surfaced, so after a transient network failure the form shows agent_max_rounds/token budget/hard max/stream timeout as "0". Failure scenario: load fails silently, user toggles "Confirmar envio de email" and taps Salvar — save() (line 266-275) writes agent_max_rounds=0, agent_input_token_budget=0, etc., breaking agent execution server-side. Same pattern in RemindersVM.load (line 152 — blank reminder_email_to etc. saved), SistemaVM.load (line 479 — app_public_url blanked) and AIDefaultsVM.load (SettingsModelsSections.swift:143).

**Fix:** Surface the load error and disable Save (or skip prefill) until an initial getSettings() has succeeded.

### Odysseus/Features/Email/EmailView.swift:39
**Failed email fetch renders as "(sem conteúdo)" and still marks the message read**

EmailViewModel.read() swallows errors with `try? await api.emailRead(m.uid)` and then unconditionally sets the local isRead flag and fires emailMarkRead before knowing whether the fetch succeeded. Failure scenario: network hiccup or server error when opening a message — EmailReader shows "(sem conteúdo)" as if the email body were empty (no error, no retry), and the message is marked read locally and on the server even though the user never saw it.

**Fix:** Propagate the fetch error to EmailReader (error + retry state) and only mark read after emailRead succeeds.

### Odysseus/Features/Settings/SettingsAdminSections.swift:761
**Admin user deletion fires on a single tap with no confirmation**

In UsuariosSection each user card has `Button("Remover", role: .destructive) { Task { await vm.remove(u) } }` which immediately calls DELETE /api/auth/users/{username}. Failure scenario: one mis-tap in the user list permanently deletes an account (and its server-side data) with no undo — inconsistent with the app's own patterns (Danger Zone wipes and email-account removal both confirm via alert).

**Fix:** Gate remove(u) behind a confirmation alert like the "Remover conta?" alert in EmailAccountsView.

### Odysseus/Features/Voice/VoiceInputManager.swift:25
**Dictation recognizer hard-coded to pt-BR despite 44 shipped localizations**

`SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))` is the only recognizer ever created, and the unavailable-error string is also pt-BR-specific (line 98). Failure scenario: any non-Portuguese-speaking user of the localized App Store build taps the mic in chat — their speech is transcribed through the pt-BR model and comes out mangled, with no way to change the dictation language.

**Fix:** Initialize the recognizer from LocalizationManager.shared.locale (or Locale.current) with pt-BR as fallback.

### Odysseus/Features/Localization/Localization.swift:133
**zh matcher returns Traditional (HK) for Simplified-script device codes zh-Hans-HK / zh-Hans-MO**

match(systemCode:) tests region before script: `if c.hasPrefix("yue") || c.contains("-hk") || c.contains("-mo") { return .zhHK }` runs before the `hant` check and there is no `hans` check at all. A user whose iPhone language is Chinese Simplified with region Hong Kong or Macau (preferredLanguages = ["zh-Hans-HK"] / ["zh-Hans-MO"] — a real, common iOS combination) gets the whole app in Traditional Chinese (zh-HK) in Automatic mode instead of zh-Hans.

**Fix:** Check the script subtag first: `if c.contains("hans") { return .zhHans }` before the -hk/-mo region test.

### Odysseus/Resources/Info.plist:32
**Permission usage descriptions are Portuguese-only; no InfoPlist.strings in any of the 44 lproj**

NSFaceIDUsageDescription, NSLocalNetworkUsageDescription, NSMicrophoneUsageDescription and NSSpeechRecognitionUsageDescription (Info.plist:32-39, and Info-macOS.plist:36-41) are hardcoded in Portuguese, and every lproj contains only Localizable.strings — no InfoPlist.strings. A Japanese/German/Arabic user tapping the mic button or hitting the Face ID lock gets an iOS system permission alert whose explanation line is Portuguese (e.g. "Para ditar mensagens por voz."), which reads as untrustworthy and drives denials in 43 of the 44 shipped languages.

**Fix:** Add InfoPlist.strings to each lproj with translated values for the four usage-description keys.

### Odysseus/Resources/hi.lproj/Localizable.strings:241
**Hindi "%lld de %lld linhas" inverts the arguments' meaning (no positional specifiers)**

The source key means "<filtered> of <total> lines" (SettingsAdminSections.swift:665 passes filteredLogs.count first, logs.count second). The Hindi value "%lld में से %lld पंक्तियाँ" uses the "X में से Y" construction, which means "Y out of X" — so with 5 matching lines out of 100 the footer renders "5 में से 100 पंक्तियाँ" = "100 lines out of 5", the exact inverse. All other 43 catalogs keep an order-compatible phrasing; only hi is inverted and .strings supports positional args.

**Fix:** Change the hi value to "%2$lld में से %1$lld पंक्तियाँ".

### Odysseus/Features/Compare/CompareView.swift:140
**"Modelo %@" is translated in all 44 catalogs but rendered via Text(String) — never localized**

`Text(model.wrappedValue?.name ?? "Modelo \(title)")` — the ?? expression is a String, so the non-localizing Text(StringProtocol) init is chosen and the catalog key "Modelo %@" (= "Model %@" in en.lproj:220, translated in all catalogs) is never looked up. On opening the Compare screen before picking models, English/Japanese/etc. users see the Portuguese placeholders "Modelo A" / "Modelo B" in the two column menus.

**Fix:** Branch explicitly: `if let name = model.wrappedValue?.name { Text(name) } else { Text("Modelo \(title)") }` so the literal goes through LocalizedStringKey.

### Odysseus/Features/Research/DeepResearchView.swift:236
**Deep Research settings grid and library rows have unlocalizable/verbatim strings — mixed-language screen**

labeledMenuRaw renders `Text(label.uppercased())` (line 236) and `Text(value)` (line 239) — String, verbatim — so the menu labels "Rounds"/"Format"/"Search"/"Endpoint"/"Model" (lines 164-175, also absent from all catalogs) and the selected value "Default" can never translate, while the Menu's own Button("Default") row DOES translate (ja "デフォルト"): a Japanese user opens the menu, picks デフォルト, and the closed field shows "Default". Library rows add un-extracted keys: `Text(failed ? "no results" : "\(job.source_count ?? 0) sources")` (line 191, also verbatim ternary) and `Text("· \(r) rounds")` (line 193, key "· %lld rounds" missing from all catalogs) — English hardcoded next to the translated "Past research"/"Relatório visual" strings on the same screen.

**Fix:** Uppercase via .textCase(.uppercase) on Text(LocalizedStringKey(label)), render values through LocalizedStringKey, and add the missing keys (Rounds/Format/Search/Endpoint/Model/no results/%lld sources/· %lld rounds) to all catalogs.

### Odysseus/Features/Research/ResearchGraph.swift:259
**ResearchRunner 1 Hz timer Task never stops on completion or pane close — permanent leak and elapsed keeps counting**

startTimer() spawns `Task { while !Task.isCancelled { elapsed = ... ; sleep(1s) } }` which strongly captures self. cancel() is only called from start()/startPreview()/close(), and close() only runs from the card's X button. Failure scenario 1: a research run finishes (evt.final / error) — the stream task returns but the timer keeps ticking, so the completed card shows 'complete · … · MM:SS' with the elapsed time still counting up forever. Failure scenario 2: the user closes the Deep Research pane via the pane ×/expand controls (workspace.close) or navigates the workspace away — DeepResearchView has no onDisappear/deinit hook, the timer Task retains the ResearchRunner, so the runner and its 1 Hz task run for the rest of the app's life; one leaked runner+timer accumulates per open/close cycle, and an in-flight SSE research stream also keeps streaming in the background (up to the 7200 s resource cap).

**Fix:** Cancel the timer when the run reaches complete/error, and cancel task+timer from DeepResearchView.onDisappear (or make the timer capture self weakly and stop when self is nil).

### Odysseus/App/OdysseusApp.swift:120
**Biometric app-lock auto-prompt fires while the app is backgrounding, so returning to foreground never auto-prompts**

relockIfNeeded() sets locked=true on scenePhase == .background; the LockView overlay is inserted and rendered during the backgrounding transition (that render is what redacts the snapshot), so its `.task { unlock() }` runs right then — LAContext.evaluatePolicy called while the app is not active fails immediately (system cancel). When the user returns to the foreground the LockView is already in the hierarchy, `.task` does not re-fire, and no Face ID prompt appears: every background→foreground cycle with app-lock enabled requires manually tapping 'Desbloquear com Face ID', contradicting the documented 'Auto-prompts on appear' behavior (auto-prompt only works on cold launch).

**Fix:** Also trigger unlock() from RootView's onChange(of: scenePhase) when newPhase == .active && app.locked (and skip the prompt attempt while the phase isn't active).

### Odysseus/Features/Settings/SettingsSections.swift:124
**Password change leaves the old password in the Keychain for silent auto-login**

changePassword() calls api.changePassword and clears only the text fields. If the user logged in with 'Manter conectado', Keychain.passwordKey still holds the OLD password (saved in AppState.login at AppState.swift:107). On the next cold launch after the session cookie expires, tryAutoLogin (AppState.swift:72-94) replays the stale password → 401 → user is unexpectedly dumped to the login screen, and every subsequent cold launch fires another failed login attempt with the old credential, which can trip server-side lockout/2FA throttling.

**Fix:** After a successful change, update Keychain.passwordKey with the new password when saved credentials exist (or delete the saved credential pair).

## Plausíveis (1 das 2 lentes confirmou — re-checar antes de agir) (4)

### Odysseus/Models/Models.swift:337
**SessionDetail decodes history all-or-nothing — one malformed row silently blanks the whole chat**

Message.init(from:) only throws at `decoder.container(keyedBy:)`, so a single non-object element (a JSON null or string emitted for one bad DB row) makes the entire `[Message]` decode under `history` fail; the fallback chain then tries `.messages`/`.msgs` and settles on `[]`. ChatViewModel marks historyLoaded=true, so the conversation opens completely empty with no error and no retry — indistinguishable from the chat having been wiped. The same all-or-nothing pattern hits EmailListResponse.emails (EmailModels.swift:95), where one bad row renders the inbox empty with error == nil.

**Fix:** Decode element-wise via an unkeyed container (lossy array), skipping only the elements that fail instead of discarding the array.

### Odysseus/Features/Notes/NotesView.swift:26
**Editing an archived note silently unarchives it (archived hardcoded to false on save)**

NotesViewModel.save() always builds `NotePayload(title:content:archived: false, pinned: nil)` for both create and update. Failure scenario: user switches to the "arquivadas" view, taps an archived note to fix a typo, hits Salvar — updateNote PUTs archived:false and the note silently jumps back to the active list.

**Fix:** Pass the note's current archived value (or nil to leave it untouched) in save(id:title:content:).

### Odysseus/Features/Settings/SettingsIntegrationAdd.swift:69
**Malformed Args/Env JSON in the MCP add form is silently replaced with []/{}**

`(try? JSONSerialization.jsonObject(with: Data(args.utf8))) ?? []` and the env equivalent swallow parse failures. Failure scenario: user hand-edits the Args JSON on a phone keyboard and introduces a typo (missing quote/bracket) — the app POSTs the MCP server with empty args and env, the server registers a broken stdio server (e.g. bare `npx`), and no error is ever shown during creation.

**Fix:** Validate both JSON fields before save() and set vm.error instead of defaulting to empty collections.

### Odysseus/Features/Settings/SettingsAdminSections.swift:97
**userPath bypasses encPath — "/" in a username is not escaped in /api/auth/users/{username}**

userPath uses `.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)`, and urlPathAllowed keeps "/" unescaped (verified: "a/b?c#d" → "a/b%3Fc%23d"). This is the only interpolated path in the audited scope that skips the house encPath() helper, whose doc comment exists exactly for this case. Failure scenario: a username containing "/" (created via web signup or API) makes setUserAdmin/renameUser/deleteUser target "/api/auth/users/a/b" — a different route — so managing or deleting that user from the app fails (404) or hits an unintended endpoint.

**Fix:** Replace the inline encoding with `"/api/auth/users/\(encPath(username))"`.

## Melhorias/limpeza (44)

- `Odysseus/Features/Settings/SettingsAPI.swift:36` — refreshEndpointModels never sets a per-request timeout, so the effective idle timeout is URLRequest's default 60s, not streamSession's 300s
- `Odysseus/Networking/APIClient.swift:183` — decodeList's wrapper fallback iterates obj.values in unspecified order and an empty array matches any [T], so a second array key can nondeterministically blank a list
- `Odysseus/Features/Settings/SettingsAdminSections.swift:97` — userPath() encodes usernames with .urlPathAllowed (keeps '/'), bypassing the encPath rule the codebase mandates for path ids
- `Odysseus/Features/Voice/ModelDownloadManager.swift:20` — Multi-hundred-MB Whisper model downloads use a foreground URLSession with no resume support
- `Odysseus/Networking/APIClient.swift:184` — decodeList picks an arbitrary array from the wrapper object (unordered dict iteration)
- `Odysseus/Features/Brain/BrainAPI.swift:31` — AuditResult's synthesized Decodable requires all keys — partial response reports "nothing removed"
- `Odysseus/Models/Models.swift:298` — Message top-level timestamps only decoded as Double — ISO strings silently dropped
- `Odysseus/Features/Chat/ChatViewModel.swift:71` — reloadHistory: cancelled old task's defer clobbers the new task's state
- `Odysseus/Features/Chat/ChatViewModel.swift:135` — Deep-research progress text is discarded — status collapses to generic 'Pensando'
- `Odysseus/Networking/ChatStreamClient.swift:130` — extractError returns the whole regex match — raw JSON fragment shown in the error bubble
- `Odysseus/Features/Chat/ChatViewModel.swift:147` — Hardcoded Portuguese strings injected as message content bypass localization
- `Odysseus/Features/Chat/ChatViewModel.swift:114` — removePending only removes the attachment locally — the uploaded file stays on the server, filed in the Gallery
- `Odysseus/Features/Chat/ChatScreen.swift:112` — Forced autoscroll on every stream delta — user cannot scroll up while a reply streams
- `Odysseus/Features/Chat/MessageBubble.swift:132` — TypingDots middle dot never animates
- `Odysseus/Features/Research/ResearchGraph.swift:260` — Research elapsed timer never stops on completion and leaks the runner
- `Odysseus/Features/Research/DeepResearchView.swift:292` — VisualReportView treats task cancellation as a load failure
- `Odysseus/Features/Research/DeepResearchView.swift:152` — Past-research refresh polling gives up after 3 minutes, before typical runs finish
- `Odysseus/Features/Gallery/GalleryAPI.swift:4` — No pagination: gallery capped at 100 items, research library at 20
- `Odysseus/Features/Sessions/SessionListView.swift:102` — Rename dialog accepts an empty name
- `Odysseus/Features/Library/LibraryView.swift:81` — Upload reads the whole file synchronously on the main actor
- `Odysseus/Features/Library/LibraryView.swift:34` — Directory entries from /api/personal are decoded but never shown
- `Odysseus/Features/Navigation/Workspace.swift:11` — Dead pane kind: .researchChat is never constructed
- `Odysseus/Features/Voice/VoiceInputManager.swift:62` — Entire on-device Whisper download stack is unreachable dead code; error text points to a non-existent settings screen
- `Odysseus/Features/Settings/SettingsAdminSections.swift:853` — Integration and model-endpoint "Remover" buttons delete without confirmation
- `Odysseus/Features/Brain/BrainView.swift:87` — One-tap AI memory "audit" deletes memories with no confirmation, and a decode fallback misreports the result
- `Odysseus/Features/Research/ResearchGraph.swift:130` — Live research status strings hardcoded in mixed PT/EN and rendered verbatim, absent from catalogs
- `Odysseus/Features/Settings/SettingsModelsSections.swift:97` — Endpoint card count line "%lld modelo(s)%@" never extracted — Portuguese in all 43 translations
- `Odysseus/Features/Settings/SettingsAdminSections.swift:634` — Sistema logs card: filter menu items and count chip bypass the catalogs (mixed-language row)
- `Odysseus/Features/Settings/SettingsAdminSections.swift:208` — Translated TextField placeholders never resolve (String overload) at 4 sites
- `Odysseus/App/AppState.swift:79` — Biometric prompt reasons hardcoded in Portuguese, outside the catalogs
- `Odysseus/Resources/en.lproj/Localizable.strings:31` — 13 stale keys shipped in all 44 catalogs (removed Voice/TTS UI + an old email note)
- `Odysseus/Features/Diffusion/DiffusionServersView.swift:145` — ComfyUI status badge and infoRow labels missing from catalogs — mixed badge states
- `Odysseus/Features/Email/EmailAccountsView.swift:294` — Email provider picker "Custom…" and SMTP security "None" untranslated
- `Odysseus/Features/Chat/ChatScreen.swift:229` — macOS ⌘V paste monitor is app-global, not scoped to the chat's focused composer
- `Odysseus/Features/Shared/SpeechManager.swift:54` — TTS activates AVAudioSession with .duckOthers but never deactivates it — other apps' audio stays ducked
- `Odysseus/Features/Shared/SpeechManager.swift:99` — Stale cancelled neural-TTS task clears preparingID belonging to a newer request
- `Odysseus/Features/Diffusion/ComfyUIClient.swift:78` — New URLSession created per getJSON call and never invalidated — leaks session resources on every connection test
- `Odysseus/Features/Chat/ChatScreen.swift:21` — ChatScreen.init defeats StateObject's lazy autoclosure — a throwaway ChatViewModel is built on every parent re-render
- `Odysseus/App/AppState.swift:78` — Cold launch can fire two concurrent biometric prompts (app-lock A2 + auto-login gate A1)
- `Odysseus/Features/Diffusion/ComfyUIClient.swift:63` — ComfyUIClient defaults scheme-less hosts to http:// for ANY host, unlike ServerConfig.normalize
- `Odysseus/Features/Voice/ModelDownloadManager.swift:139` — Model downloads never check the HTTP status — a 404 page gets installed as the model
- `Odysseus/App/OdysseusApp.swift:80` — macOS: biometric app-lock never re-engages on app switch (only on .background)
- `project.yml:154` — Odysseus-macOS Info.plist lacks CFBundleIconName that the iOS target needed for App Store Connect
- `project.yml:64` — No PrivacyInfo.xcprivacy privacy manifest despite required-reason API usage (UserDefaults)
