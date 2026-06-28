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
                Text("URL").font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
                TextField("https://odysseus.macrozao.online", text: $text)
                    .textFieldStyle(.plain)
                    .font(.ody(.body, design: .monospaced)).foregroundStyle(theme.fg)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .padding(10).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                HStack {
                    Button("Salvar servidor") {
                        if let url = ServerConfig.normalize(text) { app.updateServer(url); flash() }
                    }
                    .buttonStyle(.plain).foregroundStyle(theme.accent)
                    .disabled(ServerConfig.normalize(text) == nil)
                    if saved { Label("Salvo", systemImage: "checkmark.circle.fill").foregroundStyle(theme.green).font(.ody(size: 11, design: .monospaced)) }
                    Spacer()
                }
                Text("Aponte para o IP local hoje; quando expor por HTTPS, troque por https://seu-dominio.")
                    .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
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
    @State private var twoFA: Bool?
    @State private var cur = ""; @State private var nw = ""; @State private var confirm = ""
    @State private var pwMsg: String?
    @State private var pwOK = false
    // Opt-in biometric security (default OFF — see BiometricLock).
    @AppStorage(BiometricLock.appLockKey) private var appLock = false
    @AppStorage(BiometricLock.autoLoginKey) private var bioAutoLogin = false

    var body: some View {
        SettingsScroll("Conta", subtitle: "Sua sessão e segurança.") {
            SettingsCard {
                row("Usuário", value: app.username ?? "—")
                Divider().overlay(theme.border)
                HStack {
                    Text("2FA").font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                    Spacer()
                    switch twoFA {
                    case .some(true): Label("Ativado", systemImage: "checkmark.shield.fill").foregroundStyle(theme.green)
                    case .some(false): Text("Desativado").foregroundStyle(theme.secondaryText)
                    case .none: ProgressView().controlSize(.small)
                    }
                }
                .font(.ody(size: 12, design: .monospaced))
            }

            SettingsCard {
                Text("Trocar senha").font(.ody(.subheadline, design: .monospaced).weight(.semibold)).foregroundStyle(theme.fg)
                secure("Senha atual", $cur)
                secure("Nova senha", $nw)
                secure("Confirmar nova senha", $confirm)
                HStack {
                    Button("Atualizar senha") { Task { await changePassword() } }
                        .buttonStyle(.plain).foregroundStyle(theme.accent)
                        .disabled(cur.isEmpty || nw.count < 4 || nw != confirm)
                    if let m = pwMsg {
                        Text(m).font(.ody(size: 11, design: .monospaced)).foregroundStyle(pwOK ? theme.green : theme.accent)
                    }
                    Spacer()
                }
            }

            SettingsCard {
                Text("Segurança (\(BiometricLock.label))").font(.ody(.subheadline, design: .monospaced).weight(.semibold)).foregroundStyle(theme.fg)
                if BiometricLock.available {
                    Toggle(isOn: $appLock) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bloquear o app").font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                            Text("Pede \(BiometricLock.label) ao abrir e ao voltar pro app.")
                                .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                        }
                    }.tint(theme.accent)
                    Divider().overlay(theme.border)
                    Toggle(isOn: $bioAutoLogin) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exigir no login automático").font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                            Text("Pede \(BiometricLock.label) antes de usar a senha salva.")
                                .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                        }
                    }.tint(theme.accent)
                    Text("Opcional — desligado por padrão.")
                        .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                } else {
                    Text("Biometria/senha do dispositivo indisponível neste aparelho.")
                        .font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
                }
            }

            SettingsCard {
                Button(role: .destructive) { Task { await app.logout(); dismiss() } } label: {
                    Label("Sair da conta", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.plain).foregroundStyle(theme.accent)
            }
        }
        .task { twoFA = try? await app.api.twoFAEnabled() }
    }

    private func changePassword() async {
        do { try await app.api.changePassword(current: cur, new: nw); pwOK = true; pwMsg = "Senha atualizada"; cur = ""; nw = ""; confirm = "" }
        catch { pwOK = false; pwMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(label)).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
            Spacer()
            Text(value).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.secondaryText)
        }
    }
    private func secure(_ ph: String, _ bind: Binding<String>) -> some View {
        SecureField(ph, text: bind)
            .textFieldStyle(.plain).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
            .padding(10).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
}

// MARK: - Search

@MainActor final class SearchSettingsVM: ObservableObject {
    @Published var provider = "searxng"
    @Published var count = "5"
    @Published var url = ""
    @Published var key = ""
    @Published var cx = ""
    @Published var status = ""
    // Deep Research runtime settings
    @Published var maxTokens = "16384"
    @Published var extractTimeout = "90"
    @Published var extractParallel = "3"
    @Published var runTimeout = "1800"
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    static let providers = ["searxng", "duckduckgo", "brave", "google_pse", "tavily", "serper", "disabled"]
    static let labels = ["searxng": "SearXNG", "duckduckgo": "DuckDuckGo", "brave": "Brave Search",
                         "google_pse": "Google PSE", "tavily": "Tavily", "serper": "Serper", "disabled": "Desativado"]
    static let needsKey: Set<String> = ["brave", "google_pse", "tavily", "serper"]
    static let keyField = ["brave": "brave_api_key", "google_pse": "google_pse_key", "tavily": "tavily_api_key", "serper": "serper_api_key"]

    func load() async {
        guard let s = try? await api.getSettings() else { return }
        provider = s.string("search_provider").isEmpty ? "searxng" : s.string("search_provider")
        count = String(s.int("search_result_count", default: 5))
        url = s.string("search_url")
        cx = s.string("google_pse_cx")
        if let kf = Self.keyField[provider] { key = s.string(kf) }
        maxTokens = String(s.int("research_max_tokens", default: 16384))
        extractTimeout = String(s.int("research_extraction_timeout_seconds", default: 90))
        extractParallel = String(s.int("research_extraction_concurrency", default: 3))
        runTimeout = String(s.int("research_run_timeout_seconds", default: 1800))
    }

    func save() async {
        var body: [String: Any] = ["search_provider": provider, "search_result_count": Int(count) ?? 5]
        if provider == "searxng" { body["search_url"] = url }
        if provider == "google_pse" { body["google_pse_cx"] = cx }
        if let kf = Self.keyField[provider], !key.isEmpty { body[kf] = key }
        for (k, v) in [("research_max_tokens", maxTokens), ("research_extraction_timeout_seconds", extractTimeout),
                       ("research_extraction_concurrency", extractParallel), ("research_run_timeout_seconds", runTimeout)] {
            if let n = Int(v) { body[k] = n }
        }
        do { try await api.saveSettings(body); status = "Salvo" }
        catch { status = "Falha ao salvar" }
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
                        Button(SearchSettingsVM.labels[p] ?? p) { vm.provider = p; Task { await vm.save() } }
                    }
                } label: { menuLabel(SearchSettingsVM.labels[vm.provider] ?? vm.provider) }

                label("Resultados por busca")
                field($vm.count) { Task { await vm.save() } }

                if vm.provider == "searxng" {
                    label("URL (opcional)")
                    field($vm.url) { Task { await vm.save() } }
                }
                if SearchSettingsVM.needsKey.contains(vm.provider) {
                    label("API key")
                    field($vm.key, secure: true) { Task { await vm.save() } }
                }
                if vm.provider == "google_pse" {
                    label("Search Engine ID (CX)")
                    field($vm.cx) { Task { await vm.save() } }
                }
                if !vm.status.isEmpty {
                    Text(vm.status).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.green)
                }
            }
            SettingsCard {
                Text("Deep Research").font(.ody(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(theme.fg)
                Text("Tempos de execução da pesquisa profunda. O modelo é escolhido em Padrões de IA.")
                    .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) { label("Max tokens"); field($vm.maxTokens) { Task { await vm.save() } } }
                    VStack(alignment: .leading, spacing: 3) { label("Extract paralelo"); field($vm.extractParallel) { Task { await vm.save() } } }
                }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) { label("Extract timeout (s)"); field($vm.extractTimeout) { Task { await vm.save() } } }
                    VStack(alignment: .leading, spacing: 3) { label("Run timeout (s)"); field($vm.runTimeout) { Task { await vm.save() } } }
                }
            }
        }
        .task { await vm.load() }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
    }
    private func menuLabel(_ s: String) -> some View {
        HStack { Text(s).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.ody(size: 9)).foregroundStyle(theme.secondaryText) }
            .padding(10).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
    @ViewBuilder private func field(_ bind: Binding<String>, secure: Bool = false, onCommit: @escaping () -> Void) -> some View {
        Group {
            if secure { SecureField("", text: bind) } else { TextField("", text: bind) }
        }
        .textFieldStyle(.plain).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
        .autocorrectionDisabled().textInputAutocapitalization(.never)
        .onSubmit(onCommit)
        .padding(10).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
}

// MARK: - Email (native, consistent with the other sections)

struct EmailSection: View {
    @StateObject private var vm: EmailAccountsViewModel
    @Environment(\.theme) private var theme
    @State private var showAdd = false
    init(app: AppState) { _vm = StateObject(wrappedValue: EmailAccountsViewModel(api: app.api)) }

    var body: some View {
        SettingsScroll("Contas de email", subtitle: "Conecte contas IMAP/SMTP para ler e enviar.") {
            Button { showAdd = true } label: {
                Label("Adicionar conta", systemImage: "plus")
                    .font(.ody(.subheadline, design: .monospaced))
            }
            .buttonStyle(.plain).foregroundStyle(theme.accent)

            if vm.accounts.isEmpty && vm.loading {
                ProgressView().tint(theme.accent)
            } else if vm.accounts.isEmpty {
                Button { showAdd = true } label: {
                    SettingsCard {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.plus").font(.ody(size: 22)).foregroundStyle(theme.accent)
                            Text("Nenhuma conta — adicione uma conta IMAP.")
                                .font(.ody(size: 12, design: .monospaced)).foregroundStyle(theme.secondaryText)
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
                            .font(.ody(.subheadline, design: .monospaced).weight(.semibold)).foregroundStyle(theme.fg)
                        if acc.isDefault {
                            Text("padrão").font(.ody(size: 9, design: .monospaced)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1).background(theme.accent, in: Capsule())
                        }
                        Spacer()
                    }
                    Text(acc.subtitle).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText).lineLimit(1)
                    HStack {
                        Spacer()
                        if !acc.isDefault {
                            Button("Tornar padrão") { Task { await vm.makeDefault(acc) } }
                                .buttonStyle(.plain).foregroundStyle(theme.fg)
                        }
                        Button("Remover", role: .destructive) { Task { await vm.delete(acc) } }
                            .buttonStyle(.plain).foregroundStyle(theme.accent)
                    }
                    .font(.ody(size: 12, design: .monospaced))
                }
            }
            if let e = vm.error { Text(e).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.accent) }
        }
        .task { await vm.load() }
        .sheet(isPresented: $showAdd) {
            AddEmailAccountView { payload in await vm.add(payload) }
        }
    }
}

// MARK: - Placeholder (sections not yet native)

struct PlaceholderSection: View {
    let section: SettingsSection
    @Environment(\.theme) private var theme
    var body: some View {
        SettingsScroll(section.title) {
            SettingsCard {
                HStack(spacing: 10) {
                    Image(systemName: section.icon).font(.ody(size: 22)).foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Em construção nesta tela").font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                        Text("Esta seção do admin ainda será portada para nativo. Por enquanto, use a versão web.")
                            .font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
                    }
                    Spacer()
                }
            }
        }
    }
}
