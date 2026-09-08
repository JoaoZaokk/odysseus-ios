import SwiftUI

// MARK: - Server

struct ServerSection: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.theme) private var theme
    @State private var text = ""
    @State private var saved = false

    var body: some View {
        SettingsScroll("Servidor", subtitle: "Endereço do servidor Odysseus.") {
            SettingsCard {
                Text("URL").font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
                TextField("https://odysseus.example.com", text: $text)
                    .textFieldStyle(.plain)
                    .font(.ody(.body)).foregroundStyle(theme.fg)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .padding(10).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                HStack {
                    Button("Salvar servidor") {
                        if let url = ServerConfig.normalize(text) { app.updateServer(url); flash() }
                    }
                    .buttonStyle(.plain).foregroundStyle(theme.accent)
                    .disabled(ServerConfig.normalize(text) == nil)
                    if saved { Label("Salvo", systemImage: "checkmark.circle.fill").foregroundStyle(theme.green).font(.ody(size: 11)) }
                    Spacer()
                }
                Text("Aponte para o IP local hoje; quando expor por HTTPS, troque por https://seu-dominio.")
                    .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
            }
        }
        .onAppear { text = app.serverConfig.baseURL.absoluteString }
    }

    private func flash() { saved = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false } }
}

// MARK: - Account

struct AccountSection: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var twoFA: Bool?
    @State private var showTwoFA = false
    @State private var cur = ""; @State private var nw = ""; @State private var confirm = ""
    @State private var pwMsg: String?
    @State private var pwOK = false
    // Opt-in biometric security (default OFF — see BiometricLock).
    @AppStorage(BiometricLock.appLockKey) private var appLock = false
    @AppStorage(BiometricLock.autoLoginKey) private var bioAutoLogin = false
    @AppStorage("chat.sensitiveBlur") private var sensitiveBlur = false
    @AppStorage(TaskNotificationPoller.enabledKey) private var taskNotifications = false

    var body: some View {
        SettingsScroll("Conta", subtitle: "Sua sessão e segurança.") {
            SettingsCard {
                row("Usuário", value: app.username ?? "—")
                Rectangle().fill(theme.border).frame(height: 1)
                // Tappable: 1.8 showed the state here and could change it nowhere.
                Button { showTwoFA = true } label: {
                    HStack {
                        Text("2FA").font(.ody(.subheadline)).foregroundStyle(theme.fg)
                        Spacer()
                        switch twoFA {
                        case .some(true): Label("Ativado", systemImage: "checkmark.shield.fill").foregroundStyle(theme.green)
                        case .some(false): Text("Desativado").foregroundStyle(theme.secondaryText)
                        case .none: ProgressView().controlSize(.small)
                        }
                        Image(systemName: "chevron.right").foregroundStyle(theme.secondaryText)
                    }
                    .font(.ody(size: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            SettingsCard {
                Text("Trocar senha").font(.ody(.subheadline).weight(.semibold)).foregroundStyle(theme.fg)
                secure("Senha atual", $cur)
                secure("Nova senha", $nw)
                secure("Confirmar nova senha", $confirm)
                HStack {
                    Button("Atualizar senha") { Task { await changePassword() } }
                        .buttonStyle(.plain).foregroundStyle(theme.accent)
                        .disabled(cur.isEmpty || nw.count < 4 || nw != confirm)
                    if let m = pwMsg {
                        Text(LocalizedStringKey(m)).font(.ody(size: 11)).foregroundStyle(pwOK ? theme.green : theme.danger)
                    }
                    Spacer()
                }
            }

            SettingsCard {
                Text("Segurança (\(BiometricLock.label))").font(.ody(.subheadline).weight(.semibold)).foregroundStyle(theme.fg)
                if BiometricLock.available {
                    Toggle(isOn: $appLock) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bloquear o app").font(.ody(.subheadline)).foregroundStyle(theme.fg)
                            Text("Pede \(BiometricLock.label) ao abrir e ao voltar pro app.")
                                .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                        }
                    }.tint(theme.accent)
                    Rectangle().fill(theme.border).frame(height: 1)
                    Toggle(isOn: $bioAutoLogin) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exigir no login automático").font(.ody(.subheadline)).foregroundStyle(theme.fg)
                            Text("Pede \(BiometricLock.label) antes de usar a senha salva.")
                                .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                        }
                    }.tint(theme.accent)
                    Text("Opcional — desligado por padrão.")
                        .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                } else {
                    Text("Biometria/senha do dispositivo indisponível neste aparelho.")
                        .font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
                }
            }

            SettingsCard {
                Text("Privacidade").font(.ody(.subheadline).weight(.semibold)).foregroundStyle(theme.fg)
                Toggle(isOn: $sensitiveBlur) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Borrar dados sensíveis").font(.ody(.subheadline)).foregroundStyle(theme.fg)
                        Text("Esconde emails, chaves de API, tokens e senhas nas respostas até você tocar.")
                            .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                    }
                }.tint(theme.accent)
                Text("Opcional — desligado por padrão.")
                    .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
            }

            SettingsCard {
                Text("Notificações").font(.ody(.subheadline).weight(.semibold)).foregroundStyle(theme.fg)
                Toggle(isOn: Binding(get: { taskNotifications }, set: { on in
                    taskNotifications = on
                    if on { Task { _ = await TaskNotificationPoller.authorized(); app.startTaskNotifications() } }
                    else { app.stopTaskNotifications() }
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notificações de tarefas e lembretes").font(.ody(.subheadline)).foregroundStyle(theme.fg)
                        Text("Avisa neste aparelho quando um lembrete ou tarefa terminar, com o app aberto.")
                            .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                    }
                }.tint(theme.accent)
            }

            // The permanent door for someone who wants to rate the app on
            // their own terms — the system prompt is rare and not summonable.
            SettingsCard {
                row("Versão", value: Self.versionString)
                #if os(iOS)
                Rectangle().fill(theme.border).frame(height: 1)
                Button {
                    openURL(URL(string: "https://apps.apple.com/app/id6783977350?action=write-review")!)
                } label: {
                    Label("Avaliar o Odysseus", systemImage: "star")
                }
                .buttonStyle(.plain).foregroundStyle(theme.accent).font(.ody(.subheadline))
                #endif
            }

            SettingsCard {
                Button(role: .destructive) { Task { await app.logout(); dismiss() } } label: {
                    Label("Sair da conta", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.plain).foregroundStyle(theme.danger)
            }
        }
        .task { twoFA = try? await app.api.twoFAEnabled() }
        .sheet(isPresented: $showTwoFA) {
            TwoFactorView(app: app) { twoFA = $0 }
        }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func changePassword() async {
        do { try await app.api.changePassword(current: cur, new: nw); pwOK = true; pwMsg = "Senha atualizada"; cur = ""; nw = ""; confirm = "" }
        catch { pwOK = false; pwMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(label)).font(.ody(.subheadline)).foregroundStyle(theme.fg)
            Spacer()
            Text(value).font(.ody(.subheadline)).foregroundStyle(theme.secondaryText)
        }
    }
    private func secure(_ ph: String, _ bind: Binding<String>) -> some View {
        SecureField(LocalizedStringKey(ph), text: bind)
            .textFieldStyle(.plain).font(.ody(.subheadline)).foregroundStyle(theme.fg)
            .padding(10).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
}

// MARK: - Search

@MainActor final class SearchSettingsVM: ObservableObject {
    @Published var provider = "searxng"
    @Published var count = "5"
    @Published var url = ""
    /// One slot per provider, not one shared slot. A single `key` meant the menu's
    /// `provider = p; save()` uploaded the *previous* provider's secret under the
    /// *new* provider's settings name — Brave's key stored as `tavily_api_key`.
    @Published var keys: [String: String] = [:]
    @Published var cx = ""
    @Published var status = ""
    @Published var statusIsFailure = false
    @Published var testing = false
    /// Backup providers, in order, tried when the primary fails. Empty means
    /// the server's own default (DuckDuckGo) — which is the one thing a
    /// self-hoster who chose SearXNG for privacy would want to turn off, and
    /// until now the web was the only place to do it.
    @Published var fallbackChain: [String] = []
    // Deep Research runtime settings
    @Published var maxTokens = "16384"
    @Published var extractTimeout = "90"
    @Published var extractParallel = "3"
    @Published var runTimeout = "1800"
    /// False until `load()` has succeeded. Saving before that would post the
    /// app's placeholder values over the server's real ones.
    @Published private(set) var loaded = false
    /// Set the moment the user edits the key field. Only then is the key
    /// posted — the server blanks every key in GET for non-admins, so posting
    /// the (empty) field unedited would wipe the admin's key.
    private(set) var keyDirty = false
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    /// The credential field edits whichever provider is selected right now.
    var keyBinding: Binding<String> {
        Binding(get: { self.keys[self.provider] ?? "" },
                set: { self.keys[self.provider] = $0; self.keyDirty = true })
    }

    /// The web's ranges (settings.js). `research_max_tokens` is the one the
    /// server never clamps: 0 or a negative reaches the model provider and
    /// breaks every Deep Research run until an admin fixes it by hand.
    static func clampedTokens(_ v: String) -> Int { max(1024, Int(v) ?? 16384) }
    static func clampedExtractTimeout(_ v: String) -> Int { min(3600, max(15, Int(v) ?? 90)) }
    static func clampedParallel(_ v: String) -> Int { min(12, max(1, Int(v) ?? 3)) }
    /// 0 means "no cap"; anything else is a minute to a day.
    static func clampedRunTimeout(_ v: String) -> Int {
        let n = Int(v) ?? 1800
        return n == 0 ? 0 : min(86400, max(60, n))
    }

    static let providers = ["searxng", "duckduckgo", "brave", "google_pse", "tavily", "serper", "disabled"]
    static let labels = ["searxng": "SearXNG", "duckduckgo": "DuckDuckGo", "brave": "Brave Search",
                         "google_pse": "Google PSE", "tavily": "Tavily", "serper": "Serper", "disabled": "Desativado"]
    static let needsKey: Set<String> = ["brave", "google_pse", "tavily", "serper"]
    static let keyField = ["brave": "brave_api_key", "google_pse": "google_pse_key", "tavily": "tavily_api_key", "serper": "serper_api_key"]

    func load() async {
        guard let s = try? await api.getSettings() else { return }
        loaded = true
        keyDirty = false
        provider = s.string("search_provider").isEmpty ? "searxng" : s.string("search_provider")
        fallbackChain = (s.dict["search_fallback_chain"] as? [String]) ?? []
        count = String(s.int("search_result_count", default: 5))
        url = s.string("search_url")
        cx = s.string("google_pse_cx")
        for (p, kf) in Self.keyField { keys[p] = s.string(kf) }
        maxTokens = String(s.int("research_max_tokens", default: 16384))
        extractTimeout = String(s.int("research_extraction_timeout_seconds", default: 90))
        extractParallel = String(s.int("research_extraction_concurrency", default: 3))
        runTimeout = String(s.int("research_run_timeout_seconds", default: 1800))
    }

    func save() async {
        if !loaded { await load() }
        guard loaded else { flash("Falha ao salvar"); return }
        // Show the value that will actually apply, not the one that was typed.
        let tokens = Self.clampedTokens(maxTokens), extract = Self.clampedExtractTimeout(extractTimeout)
        let parallel = Self.clampedParallel(extractParallel), run = Self.clampedRunTimeout(runTimeout)
        maxTokens = String(tokens); extractTimeout = String(extract)
        extractParallel = String(parallel); runTimeout = String(run)
        let results = min(50, max(1, Int(count) ?? 5))
        count = String(results)

        var body: [String: Any] = ["search_provider": provider, "search_result_count": results,
                                   "research_max_tokens": tokens, "research_extraction_timeout_seconds": extract,
                                   "research_extraction_concurrency": parallel, "research_run_timeout_seconds": run]
        if provider == "searxng" { body["search_url"] = url }
        if provider == "google_pse" { body["google_pse_cx"] = cx }
        // An emptied field is a deliberate "clear the key" — 1.8 dropped it,
        // which made a stored key impossible to remove from the app.
        if keyDirty, let kf = Self.keyField[provider] { body[kf] = keys[provider] ?? "" }
        do { try await api.saveSettings(body); keyDirty = false; flash("Salvo") }
        catch { flash("Falha ao salvar") }
    }

    /// Never the primary, never "disabled", never one already in the chain.
    var availableFallbacks: [String] {
        Self.providers.filter { $0 != provider && $0 != "disabled" && !fallbackChain.contains($0) }
    }
    func addFallback() {
        guard let p = availableFallbacks.first else { return }
        fallbackChain.append(p)
        Task { await saveChain() }
    }
    func replaceFallback(at i: Int, with p: String) {
        guard fallbackChain.indices.contains(i) else { return }
        fallbackChain[i] = p
        Task { await saveChain() }
    }
    func removeFallback(at i: Int) {
        guard fallbackChain.indices.contains(i) else { return }
        fallbackChain.remove(at: i)
        Task { await saveChain() }
    }
    /// The chain saves itself on every change, as on the web.
    func saveChain() async {
        guard loaded else { flash("Falha ao salvar"); return }
        do { try await api.saveSettings(["search_fallback_chain": fallbackChain]); flash("Salvo") }
        catch { flash("Falha ao salvar") }
    }

    /// Saves first so the test uses the key on screen, as the web does.
    func test() async {
        guard provider != "disabled" else { status = "Escolha um provedor primeiro."; statusIsFailure = true; return }
        await save()
        testing = true; defer { testing = false }
        do {
            let r = try await api.searchTest(provider: provider)
            statusIsFailure = false
            status = L("%lld resultados · %lldms", r.count, r.ms)
        } catch {
            statusIsFailure = true
            status = SettingsUI.failure(error, "Falha no teste: %@") ?? ""
        }
    }

    private func flash(_ s: String) {
        status = s; statusIsFailure = s != "Salvo"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.status = "" }
    }
}

struct SearchSection: View {
    @StateObject private var vm: SearchSettingsVM
    @Environment(\.theme) private var theme
    init(app: AppState) { _vm = StateObject(wrappedValue: SearchSettingsVM(api: app.api)) }

    var body: some View {
        SettingsScroll("Busca", subtitle: "Provedor usado para busca na web e pesquisa profunda.") {
            SettingsCard {
                label("Provedor")
                Menu {
                    ForEach(SearchSettingsVM.providers, id: \.self) { p in
                        Button(LocalizedStringKey(SearchSettingsVM.labels[p] ?? p)) { vm.provider = p; Task { await vm.save() } }
                    }
                } label: { menuLabel(SearchSettingsVM.labels[vm.provider] ?? vm.provider) }

                if vm.provider != "disabled" {
                    label("Fallbacks")
                    ForEach(Array(vm.fallbackChain.enumerated()), id: \.offset) { i, p in
                        HStack(spacing: 6) {
                            Menu {
                                ForEach(vm.availableFallbacks + [p], id: \.self) { q in
                                    Button(LocalizedStringKey(SearchSettingsVM.labels[q] ?? q)) { vm.replaceFallback(at: i, with: q) }
                                }
                            } label: { menuLabel(SearchSettingsVM.labels[p] ?? p) }
                            Button { vm.removeFallback(at: i) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).foregroundStyle(theme.secondaryText)
                        }
                    }
                    Button { vm.addFallback() } label: { Label("Adicionar fallback", systemImage: "plus") }
                        .buttonStyle(.plain).font(.ody(size: 11)).foregroundStyle(theme.accent)
                        .disabled(vm.availableFallbacks.isEmpty)
                }

                label("Resultados por busca")
                field($vm.count, numeric: true) { Task { await vm.save() } }

                if vm.provider == "searxng" {
                    label("URL (opcional)")
                    field($vm.url) { Task { await vm.save() } }
                }
                if SearchSettingsVM.needsKey.contains(vm.provider) {
                    label("API key")
                    field(vm.keyBinding, secure: true) { Task { await vm.save() } }
                }
                if vm.provider == "google_pse" {
                    label("ID do mecanismo de busca (CX)")
                    field($vm.cx) { Task { await vm.save() } }
                }
                HStack {
                    Button(vm.testing ? "Testando…" : "Testar") { Task { await vm.test() } }
                        .buttonStyle(.plain).foregroundStyle(theme.accent).font(.ody(size: 12))
                        .disabled(vm.testing || vm.provider == "disabled")
                    Spacer()
                }
                if !vm.status.isEmpty {
                    Text(LocalizedStringKey(vm.status)).font(.ody(size: 11))
                        .foregroundStyle(vm.statusIsFailure ? theme.danger : theme.green)
                }
            }
            SettingsCard {
                Text("Deep Research").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
                Text("Tempos de execução da pesquisa profunda. O modelo é escolhido em Padrões de IA.")
                    .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) { label("Max tokens"); field($vm.maxTokens, numeric: true) { Task { await vm.save() } } }
                    VStack(alignment: .leading, spacing: 3) { label("Extração paralela"); field($vm.extractParallel, numeric: true) { Task { await vm.save() } } }
                }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) { label("Timeout da extração (s)"); field($vm.extractTimeout, numeric: true) { Task { await vm.save() } } }
                    VStack(alignment: .leading, spacing: 3) { label("Timeout de execução (s)"); field($vm.runTimeout, numeric: true) { Task { await vm.save() } } }
                }
            }
        }
        .task { await vm.load() }
        // Leaving the screen — "Concluído", another section — used to discard
        // everything typed without a Return. The guard inside `save()` keeps a
        // failed load from turning this into a post of placeholder values.
        .onDisappear { if vm.loaded { Task { await vm.save() } } }
    }

    private func label(_ s: String) -> some View {
        Text(LocalizedStringKey(s)).font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
    }
    private func menuLabel(_ s: String) -> some View {
        HStack { Text(LocalizedStringKey(s)).font(.ody(.subheadline)).foregroundStyle(theme.fg); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.ody(size: 9)).foregroundStyle(theme.secondaryText) }
            .padding(10).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
    private func field(_ bind: Binding<String>, secure: Bool = false, numeric: Bool = false,
                       onCommit: @escaping () -> Void) -> some View {
        CommitField(text: bind, secure: secure, numeric: numeric, onCommit: onCommit)
    }
}

/// A settings text field that commits on Return **and** on losing focus.
/// Eight fields in Busca committed only on Return; tapping the next field
/// and leaving silently dropped the edit.
private struct CommitField: View {
    @Binding var text: String
    var secure = false
    var numeric = false
    var onCommit: () -> Void
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure { SecureField("", text: $text) } else { TextField("", text: $text) }
        }
        .textFieldStyle(.plain).font(.ody(.subheadline)).foregroundStyle(theme.fg)
        .autocorrectionDisabled().textInputAutocapitalization(.never)
        .keyboardType(numeric ? .numberPad : .default)
        .focused($focused)
        .onSubmit(onCommit)
        .onChange(of: focused) { _, now in if !now { onCommit() } }
        .padding(10).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
}

// MARK: - Email (native, consistent with the other sections)

struct EmailSection: View {
    @StateObject private var vm: EmailAccountsViewModel
    @Environment(\.theme) private var theme
    @State private var showAdd = false
    @State private var showAutomation = false
    private let app: AppState
    init(app: AppState) { self.app = app; _vm = StateObject(wrappedValue: EmailAccountsViewModel(api: app.api)) }

    var body: some View {
        SettingsScroll("Contas de email", subtitle: "Conecte contas IMAP/SMTP para ler e enviar.") {
            HStack(spacing: 18) {
                Button { showAdd = true } label: {
                    Label("Adicionar conta", systemImage: "plus")
                        .font(.ody(.subheadline))
                }
                .buttonStyle(.plain).foregroundStyle(theme.accent)
                Button { showAutomation = true } label: {
                    Label("Automação de email", systemImage: "wand.and.stars")
                        .font(.ody(.subheadline))
                }
                .buttonStyle(.plain).foregroundStyle(theme.accent)
            }

            if vm.accounts.isEmpty && vm.loading {
                ProgressView().tint(theme.accent)
            } else if vm.accounts.isEmpty {
                Button { showAdd = true } label: {
                    SettingsCard {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.plus").font(.ody(size: 22)).foregroundStyle(theme.accent)
                            Text("Nenhuma conta — adicione uma conta IMAP.")
                                .font(.ody(size: 12)).foregroundStyle(theme.secondaryText)
                            Spacer()
                            Image(systemName: "chevron.right").font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(vm.accounts) { acc in
                SettingsCard {
                    HStack(spacing: 6) {
                        Text(acc.name.isEmpty ? acc.fromAddress : acc.name)
                            .font(.ody(.subheadline).weight(.semibold)).foregroundStyle(theme.fg)
                        if acc.isDefault {
                            Text("padrão").font(.ody(size: 9)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1).background(theme.accent, in: Capsule())
                        }
                        Spacer()
                    }
                    Text(acc.subtitle).font(.ody(size: 11)).foregroundStyle(theme.secondaryText).lineLimit(1)
                    HStack {
                        Spacer()
                        if !acc.isDefault {
                            Button("Tornar padrão") { Task { await vm.makeDefault(acc) } }
                                .buttonStyle(.plain).foregroundStyle(theme.fg)
                        }
                        Button("Remover", role: .destructive) { Task { await vm.delete(acc) } }
                            .buttonStyle(.plain).foregroundStyle(theme.danger)
                    }
                    .font(.ody(size: 12))
                }
            }
            if let e = vm.error { Text(LocalizedStringKey(e)).font(.ody(size: 11)).foregroundStyle(theme.danger) }
        }
        .task { await vm.load() }
        .sheet(isPresented: $showAutomation) { EmailAutomationView(app: app).environment(\.theme, theme) }
        .sheet(isPresented: $showAdd) {
            // onTest must be passed explicitly: its default is `{ _ in nil }` and
            // nil means success — without this, "Testar conexão" reported
            // "Conexão OK" without ever touching the network.
            AddEmailAccountView(onSave: { payload in await vm.add(payload) },
                                onTest: { payload in await vm.test(payload) })
        }
    }
}

