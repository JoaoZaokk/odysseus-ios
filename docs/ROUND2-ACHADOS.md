# Round 2 — índice completo dos achados

Gerado da auditoria de 2026-08-30. Cada linha é uma afirmação de UM agente;
só os marcados abaixo passaram por refutação adversarial. Trate o resto como
hipótese, não como dívida conhecida — 3 de 8 claims refutados caíram.

Detalhe completo (problem / move / payoff) nos journals citados no handoff.


## Qualidade

- **[strong]** Chat/session feature endpoints live inside the transport spine
  `Odysseus/Networking/APIClient.swift:271`
- **[strong]** "These JSON keys are aliases" is hand-rolled eight different ways
  `Odysseus/Models/Models.swift:212`
- **[strong]** ✅ Stream error text is re-parsed with a regex that returns the wrong substring
  `Odysseus/Networking/ChatStreamClient.swift:136`
- **[strong]** decodeList turns any decode failure into an empty list on ~15 endpoints
  `Odysseus/Networking/APIClient.swift:195`
- **[worth-doing]** Session teardown is copy-pasted between logout and server switch
  `Odysseus/App/AppState.swift:157`
- **[worth-doing]** AnyEncodable is a type eraser Swift no longer needs
  `Odysseus/Networking/APIClient.swift:432`
- **[worth-doing]** LoginResponse.empty force-unwraps a JSON round-trip to build three nils
  `Odysseus/Networking/APIClient.swift:380`
- **[worth-doing]** The two URLSession configurations are the same eight lines twice
  `Odysseus/Networking/APIClient.swift:45`
- **[minor]** sessions() re-implements decodeList thirty lines below it
  `Odysseus/Networking/APIClient.swift:275`
- **[minor]** The cookie-persistence comment contradicts the cookie jar it documents
  `Odysseus/Networking/APIClient.swift:85`
- **[strong]** SettingsAdminSections.swift stacks five layers in one 973-line file, including chrome the rest of the app imports
  `Odysseus/Features/Settings/SettingsAdminSections.swift:1`
- **[strong]** `SettingsUI.menuRow` is String-in/String-out, so callers pick values by reverse-looking-up a display label
  `Odysseus/Features/Settings/SettingsAdminSections.swift:948`
- **[strong]** ✅ Search provider is four parallel string tables plus three ad-hoc `provider ==` branches
  `Odysseus/Features/Settings/SettingsSections.swift:160`
- **[strong]** AIDefaults spells the same (endpoint, model) pair four times, with four copies of the pick handler and five copies of the save
  `Odysseus/Features/Settings/SettingsModelsSections.swift:155`
- **[strong]** Five private re-implementations of the same settings field/label/menu chrome
  `Odysseus/Features/Settings/SettingsAdminSections.swift:931`
- **[worth-doing]** SistemaVM is two view models in a trench coat, and its log level is a raw string with a special case
  `Odysseus/Features/Settings/SettingsAdminSections.swift:478`
- **[worth-doing]** Six hand-written tolerant decoders, and `?? UUID().uuidString` fabricates rows whose buttons address nothing
  `Odysseus/Features/Settings/SettingsAdminSections.swift:32`
- **[worth-doing]** `setEndpointModelVisibility` takes both lists and a flag, then throws one away
  `Odysseus/Features/Settings/SettingsAPI.swift:53`
- **[minor]** `saveJSON` returns `Bool?` where the third state is the interesting one
  `Odysseus/Features/Settings/SettingsAdminSections.swift:898`
- **[strong]** ✅ Navigation identity is keyed on a whole mutable ChatSession value
  `Odysseus/Features/Navigation/Workspace.swift:10`
- **[strong]** Two contradictory error policies for the same stream failure
  `Odysseus/Features/Chat/ChatViewModel.swift:160`
- **[strong]** `error` is a write-only @Published in both stores — five catch blocks feed nothing
  `Odysseus/Features/Chat/ChatViewModel.swift:11`
- **[strong]** ChatScreen hand-rolls the platform header that `screenChrome` exists to own
  `Odysseus/Features/Chat/ChatScreen.swift:37`
- **[strong]** A ChatViewModel is built and thrown away on every parent re-render, then configured post-hoc
  `Odysseus/Features/Chat/ChatScreen.swift:22`
- **[worth-doing]** Every message bubble observes the global SpeechManager and takes a closure it can't diff
  `Odysseus/Features/Chat/MessageBubble.swift:9`
- **[worth-doing]** The model-name shortener is re-written inline four times in this slice
  `Odysseus/Features/Chat/ChatViewModel.swift:94`
- **[worth-doing]** SidebarView hand-inlines its own `navRow`, and repeats the row wrapper three times
  `Odysseus/Features/Sessions/SessionListView.swift:34`
- **[worth-doing]** Two pt-BR literals bypass `L()` where the translation already exists in all 44 catalogues
  `Odysseus/Features/Chat/ChatViewModel.swift:230`
- **[strong]** AddEmailAccountView keeps 17 loose @State fields that are an unmodelled copy of EmailAccountPayload
  `Odysseus/Features/Email/EmailAccountsView.swift:234`
- **[strong]** EmailView's five-branch state chain makes some errors unrenderable
  `Odysseus/Features/Email/EmailView.swift:95`
- **[strong]** Calendar date handling has no canonical home — the en_US_POSIX rule is copy-pasted four times and already broken once
  `Odysseus/Features/Calendar/CalendarView.swift:206`
- **[strong]** AddEmailAccountView re-implements SettingsUI.field / menuRow / group verbatim
  `Odysseus/Features/Email/EmailAccountsView.swift:471`
- **[strong]** EmailAccountsView hand-rolls the macOS header that screenChrome already provides
  `Odysseus/Features/Email/EmailAccountsView.swift:122`
- **[strong]** EmailLoginGuide is a second, five-language localization system living beside the app's 44
  `Odysseus/Features/Email/EmailLoginHelpView.swift:95`
- **[strong]** AddEmailAccountView's contract is enforced by comments at the call sites: a defaulted onTest means "the test always passes"
  `Odysseus/Features/Email/EmailAccountsView.swift:229`
- **[worth-doing]** emailFriendlyMessage returns "sometimes a localization key, sometimes raw server text", and three copies of msg() wrap it
  `Odysseus/Features/Email/EmailAPI.swift:13`
- **[worth-doing]** The accounts list exists twice, with different destructive behaviour
  `Odysseus/Features/Email/EmailAccountsView.swift:177`
- **[worth-doing]** EmailProvider carries two dead members and a parallel domain table, and the picker hardcodes an English "Custom…"
  `Odysseus/Features/Email/EmailProviders.swift:9`
- **[worth-doing]** Decoders invent a random identity when the server omits an id
  `Odysseus/Features/Email/EmailAccount.swift:30`
- **[blocker]** ✅ Four Research controls are placebo: Format / Search / Endpoint / Model are collected and thrown away
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Research/DeepResearchView.swift:161`
- **[strong]** ResearchRun models its phase as a display String plus a shadow `error` Bool
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Research/ResearchGraph.swift:14`
- **[strong]** The view polls the runner's display string for up to 3 minutes to learn the run finished
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Research/DeepResearchView.swift:151`
- **[strong]** The preview driver is dead code, and its comment claims the real API is not wired
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Research/ResearchGraph.swift:238`
- **[strong]** `statusTitle` and `fitLabel` return String, so their already-translated text renders in Portuguese everywhere
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Research/ResearchGraph.swift:142`
- **[worth-doing]** ReportBlock.id is a content hash that collides, so repeated headings drop out of the report
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Research/ResearchReport.swift:19`
- **[worth-doing]** ReportSource.url is a String, forcing a force-unwrapped junk URL at the render site
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Research/DeepResearchView.swift:395`
- **[worth-doing]** ComfyUIClient parses JSON as `Any` and hand-rolls numeric coercion around it
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Diffusion/ComfyUIClient.swift:73`
- **[worth-doing]** DiffusionProbeVM runs three independent probes in sequence and swallows two of them
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Diffusion/DiffusionServersView.swift:44`
- **[worth-doing]** DeepResearchView re-implements SettingsCard and SettingsUI.menuRow with slightly different metrics
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Research/DeepResearchView.swift:211`
- **[worth-doing]** SSE frame plumbing is duplicated between the Research feature and the canonical stream client
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Research/ResearchAPI.swift:100`
- **[worth-doing]** Cookbook fakes install progress with a 4-second sleep
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Cookbook/CookbookView.swift:75`
- **[minor]** estimatedWeightGB has a ternary whose branches are identical and a no-op string rewrite
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Diffusion/ComfyUIClient.swift:191`
- **[minor]** The danger red is a hex literal repeated 14 times because Theme has no `danger`
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Research/ResearchGraph.swift:41`
- **[minor]** ResearchReport.subtitle is hard-coded nil and the view branches on it
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Research/ResearchReport.swift:58`
- **[strong]** `Font.ody(design:)` is a parameter the function throws away — 356 call sites pass it
  `Odysseus/Config/Theme.swift:171`
- **[strong]** Theme has a `green` role but no `danger` — so 17 hardcoded hex literals live in feature files
  `Odysseus/Config/Theme.swift:44`
- **[strong]** `lprojName: String?` is a never-nil identity wrapper left behind by the pt-BR fix
  `Odysseus/Features/Localization/Localization.swift:124`
- **[strong]** `AppLanguage.whisperCode` is dead code and a second copy of the whisper mapping
  `Odysseus/Features/Localization/Localization.swift:149`
- **[strong]** The platform seam is inverted: dead toolbar shims, while the shim call sites need is missing
  `Odysseus/Config/PlatformCompat.swift:11`
- **[worth-doing]** `AppLanguage.match` keeps a hand-maintained 39-entry table of codes the enum already knows
  `Odysseus/Features/Localization/Localization.swift:175`
- **[worth-doing]** `BackgroundPattern.none` is guarded four separate times, and the pattern is re-switched per particle per frame
  `Odysseus/Config/Backgrounds.swift:22`
- **[worth-doing]** `Theme.==` compares only `id`, so a translucent theme equals its opaque original
  `Odysseus/Config/Theme.swift:47`
- **[worth-doing]** `Appearance.fontFamily` and `ThemeStore.fontFamily` are two stores of one value, synced by hand
  `Odysseus/Config/Theme.swift:144`
- **[minor]** `ServerConfig.url` falls back to the construction its own comment says produces a 404
  `Odysseus/Config/ServerConfig.swift:82`
- **[minor]** Two hex parsers in one 251-line file
  `Odysseus/Config/Theme.swift:95`
- **[strong]** ✅ Six view models publish an `error` no view ever reads — every failure in this slice is silent
  `Odysseus/Features/Notes/NotesView.swift:7`
- **[strong]** ✅ `deletePersonal` hand-rolls query encoding with the unsafe charset the repo's own security sweep removed everywhere else
  `Odysseus/Features/Library/LibraryView.swift:53`
- **[strong]** CompareViewModel encodes "which column" as an `isA: Bool` threaded through every method instead of modelling a column
  `Odysseus/Features/Compare/CompareView.swift:68`
- **[strong]** Seven models hand-write the same lenient `init(from:)` — id-as-String-or-Int, alias keys, `try?`-with-default
  `Odysseus/Features/Brain/BrainModels.swift:19`
- **[strong]** ✅ Notes' write path has three overlapping body shapes, and `save` unconditionally sends `archived: false`
  `Odysseus/Features/Notes/NotesView.swift:26`
- **[worth-doing]** `ScheduledTask.scheduleText` builds user-facing prose in the model, which structurally cannot be localized
  `Odysseus/Features/Tasks/TasksView.swift:52`
- **[worth-doing]** Gallery loads, decodes and stores albums that nothing displays — and wraps `config.resolve` twice
  `Odysseus/Features/Gallery/GalleryView.swift:6`
- **[worth-doing]** "New note" is encoded as a `Note` with an empty-string id, decoded again in three places
  `Odysseus/Features/Notes/NotesView.swift:68`
- **[minor]** ServerSetupView guards with `#if os(iOS)` around modifiers that PlatformCompat already shims, and re-inlines LoginView's field chrome
  `Odysseus/Features/Auth/ServerSetupView.swift:49`
- **[minor]** Pinned-first ordering via `(pinned ? 1 : 0) >` is copied in two modules and destroys the server's ordering
  `Odysseus/Features/Brain/BrainView.swift:24`
- **[minor]** GalleryDetail favourites a stale value copy, so its own heart never updates
  `Odysseus/Features/Gallery/GalleryView.swift:176`
- **[strong]** SpeechManager fuses a shared one-shot speech service with the hands-free reply queue
  `Odysseus/Features/Shared/SpeechManager.swift:79`
- **[strong]** The TTS settings picker hardcodes the engine list the enum already owns, and the per-engine rows are non-exhaustive `if ==` chains
  `Odysseus/Features/Voice/VoiceSettingsView.swift:86`
- **[worth-doing]** `duplexSession` is one boolean with two unrelated meanings, so the streaming rule is written twice
  `Odysseus/Features/Shared/SpeechManager.swift:116`
- **[worth-doing]** Neural-pack ownership is split across SpeechManager and NeuralVoiceStore, which call each other
  `Odysseus/Features/Voice/NeuralVoiceStore.swift:37`
- **[worth-doing]** The same server-TTS failure is reported two different ways depending on whether the sentence was prefetched
  `Odysseus/Features/Shared/SpeechManager.swift:241`
- **[worth-doing]** The `nonisolated(unsafe)` block's stated invariant is false for four of its five members
  `Odysseus/Features/Voice/VoiceInputManager.swift:34`
- **[minor]** `msg(_:)` is a bespoke private copy of an idiom whose canonical home already exists
  `Odysseus/Features/Shared/SpeechManager.swift:688`

_83 itens._

## Arquitetura

- **[Strong]** The remote-list screen
  `Odysseus/Features/Brain/BrainView.swift:27; Odysseus/Features/Notes/NotesView.swift:18`
- **[Strong]** Features — a module nothing reads
  `Odysseus/Models/Models.swift:81; Odysseus/Networking/APIClient.swift:237`
- **[Strong]** Lenient JSON decoding
  `Odysseus/Models/Models.swift:212; Odysseus/Models/Models.swift:201`
- **[Worth exploring]** The SSE reader
  `Odysseus/Networking/ChatStreamClient.swift:22; Odysseus/Networking/ChatStreamClient.swift:48`
- **[Worth exploring]** The user-supplied server address
  `Odysseus/Config/ServerConfig.swift:64; Odysseus/Config/ServerConfig.swift:38`
- **[Speculative]** Micro pass-throughs
  `Odysseus/Features/Gallery/GalleryAPI.swift:20; Odysseus/Features/Gallery/GalleryView.swift:39`
- **[Strong]** The request description
  `Odysseus/Networking/APIClient.swift:121-201; Odysseus/Networking/APIClient.swift:166 (send(_:via:))`
- **[Strong]** The SSE reader
  `Odysseus/Networking/ChatStreamClient.swift:27-84; Odysseus/Networking/ChatStreamClient.swift:106-108`
- **[Worth exploring]** The failed-request-to-screen policy
  `Odysseus/Features/Brain/BrainView.swift:64; Odysseus/Features/Notes/NotesView.swift:44`
- **[Worth exploring]** The user-configured endpoint
  `Odysseus/Features/Voice/VoiceEndpoint.swift:97-115; Odysseus/Features/Voice/VoiceEndpoint.swift:288-306`
- **[Worth exploring]** The settings vocabulary
  `Odysseus/Features/Settings/SettingsModels.swift:90-107; Odysseus/Features/Settings/SettingsAPI.swift:5-18`
- **[Strong]** The server settings store
  `Odysseus/Features/Settings/SettingsModels.swift:88-107 (SettingsBag); Odysseus/Features/Settings/SettingsAPI.swift:5-19 (getSettings/saveSettings)`
- **[Strong]** The half-modelled voice preference
  `Odysseus/Features/Voice/VoiceEngines.swift:16-97 (STTEngine, TTSEngine); Odysseus/Features/Localization/Localization.swift:316-338 (SpeechLanguage)`
- **[Strong]** Email account creation
  `Odysseus/Features/Email/EmailAccountsView.swift:225-273 (18 @State + canSave); Odysseus/Features/Email/EmailAccountsView.swift:487-535 (applyProvider, autofill, buildPayload)`
- **[Worth exploring]** The TTS playback contract
  `Odysseus/Features/Shared/SpeechManager.swift:35-130 (published state, callbacks, queue flags); Odysseus/Features/Shared/SpeechManager.swift:222-280 (pump, prefetchNext)`
- **[Strong]** Session authority
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/App/AppState.swift:100-175; /Users/joaozao/Projetos/Odysseus-iOS/Odysseus/App/AppState.swift:114-118`
- **[Strong]** Remote-resource screen
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Notes/NotesView.swift:3-55; /Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Brain/BrainView.swift:3-76`
- **[Strong]** User-facing error text
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Networking/APIClient.swift:3-17; /Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Email/EmailAPI.swift:13-37`
- **[Worth exploring]** Voice preferences
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Voice/VoiceSettingsView.swift:19-26; /Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Shared/SpeechManager.swift:114`
- **[Worth exploring]** Themed surface
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Settings/SettingsView.swift:223-232; /Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Config/Theme.swift:10-49`
- **[Worth exploring]** Speech turn ownership
  `/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Shared/SpeechManager.swift:25-72; /Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Features/Voice/VoiceConversation.swift:195-211`
- **[Strong]** SSE frame reader and event router
  `Odysseus/Networking/ChatStreamClient.swift:40-86; Odysseus/Features/Research/ResearchAPI.swift:111-118`
- **[Strong]** Barge-in run decision
  `Odysseus/Features/Voice/BargeInMonitor.swift:311-363; Odysseus/Features/Voice/BargeInMonitor.swift:366-389`
- **[Strong]** Spoken-turn scheduler
  `Odysseus/Features/Voice/VoiceConversation.swift:420-470; Odysseus/Features/Shared/SpeechManager.swift:79-102`
- **[Strong]** Voice setting keys and their defaults
  `Odysseus/Features/Voice/VoiceEngines.swift:26; Odysseus/Features/Voice/VoiceEngines.swift:70`
- **[Worth exploring]** Odysseus wire shape as a value
  `Odysseus/Networking/APIClient.swift:118-205; Odysseus/Networking/APIClient.swift:305-307`
- **[Worth exploring]** Resolved localization table
  `Odysseus/Features/Localization/Localization.swift:280-300; Odysseus/Features/Localization/Localization.swift:186-215`
- **[Strong]** Text a user will read
  `Odysseus/Features/Localization/Localization.swift:275 (L); Odysseus/Features/Localization/Localization.swift:280 (LocalizedBundle)`
- **[Strong]** A server setting, declared once
  `Odysseus/Features/Settings/SettingsModels.swift:88 (SettingsBag); Odysseus/Features/Settings/SettingsSections.swift:145-200 (SearchSettingsVM)`
- **[Strong]** A request as a value
  `Odysseus/Networking/APIClient.swift:120-175 (request/encPath/formRequest/jsonRequest/send); Odysseus/Features/Settings/SettingsAPI.swift:31`
- **[Worth exploring]** A failure, described once
  `Odysseus/Networking/APIClient.swift:6-17 (APIError.errorDescription); Odysseus/Features/Email/EmailAPI.swift:27 (emailFriendlyMessage)`
- **[Worth exploring]** The email account editor
  `Odysseus/Features/Email/EmailAccountsView.swift:225-229 (AddEmailAccountView, onTest default); Odysseus/Features/Email/EmailAccountsView.swift:97`
- **[Worth exploring]** The wire timestamp
  `Odysseus/Models/Models.swift:5-22 (ISODate); Odysseus/Features/Calendar/CalendarModels.swift:60-93 (CalendarEvent.parse)`

_33 itens._
