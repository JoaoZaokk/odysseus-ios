import SwiftUI

// MARK: - Added Models (connected endpoints)

@MainActor final class AddedModelsVM: ObservableObject {
    @Published var endpoints: [ModelEndpoint] = []
    @Published var loading = false
    @Published var error: String?
    /// Id of the endpoint currently being re-probed, if any.
    @Published var refreshing: String?
    /// Model count from the last refresh. Kept as a number, not a sentence, so
    /// the view can build a localizable `Text` out of it.
    @Published var refreshResult: Int?
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func load() async {
        loading = true; defer { loading = false }
        do { endpoints = try await api.modelEndpoints(); self.error = nil }
        catch let e where e.isCancellation {}
        catch { self.error = SettingsUI.msg(error) }
    }
    func toggle(_ ep: ModelEndpoint) async {
        do { try await api.setEndpointEnabled(ep.id, !ep.isEnabled); await load() }
        catch { self.error = SettingsUI.failure(error, "Falha ao salvar: %@") }
    }

    /// Re-probes the endpoint. The list endpoint never probes on its own, so an
    /// endpoint that was offline when it was added shows zero models until this runs.
    func refresh(_ ep: ModelEndpoint) async {
        refreshing = ep.id; refreshResult = nil; error = nil
        defer { refreshing = nil }
        do {
            let found = try await api.refreshEndpointModels(ep.id)
            await load()
            refreshResult = found.count
        } catch {
            self.error = SettingsUI.failure(error, "Não foi possível carregar os modelos: %@",
                                            admin: "Só um administrador pode atualizar a lista de modelos.")
        }
    }
    func delete(_ ep: ModelEndpoint) async {
        do { try await api.deleteEndpoint(ep.id); await load() }
        catch { self.error = SettingsUI.failure(error, "Falha ao remover: %@") }
    }
}

struct AddedModelsSection: View {
    @StateObject private var vm: AddedModelsVM
    @Environment(\.theme) private var theme
    /// Kept so the per-model sheet can build its own view model.
    private let app: AppState
    @State private var picking: ModelEndpoint?
    @State private var removing: ModelEndpoint?
    init(app: AppState) {
        self.app = app
        _vm = StateObject(wrappedValue: AddedModelsVM(api: app.api))
    }

    var body: some View {
        SettingsScroll("Modelos conectados", subtitle: "Endpoints que você conectou. Ative, desative ou remova.") {
            if vm.loading && vm.endpoints.isEmpty {
                ProgressView().tint(theme.accent)
            }
            if let e = vm.error {
                // Through LocalizedStringKey so the fixed messages translate;
                // anything the server worded falls through to itself.
                Text(LocalizedStringKey(e)).font(.ody(size: 11)).foregroundStyle(theme.danger)
            }
            if let n = vm.refreshResult {
                Group {
                    if n == 0 { Text("Nenhum modelo encontrado. O endpoint respondeu?") }
                    else { Text("Modelos encontrados: \(n)") }
                }
                .font(.ody(size: 11))
                .foregroundStyle(n == 0 ? theme.danger : theme.green)
            }
            ForEach(vm.endpoints) { ep in card(ep) }
            if vm.endpoints.isEmpty && !vm.loading {
                Text("Nenhum endpoint conectado.").font(.ody(size: 12)).foregroundStyle(theme.secondaryText)
            }
        }
        .task { await vm.load() }
        .sheet(item: $picking) { ep in
            EndpointModelsView(app: app, endpoint: ep)
        }
        .alert(removing?.name ?? "", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remover", role: .destructive) { if let ep = removing { Task { await vm.delete(ep) } }; removing = nil }
            Button("Cancelar", role: .cancel) { removing = nil }
        } message: { Text("Isso é irreversível. Confirma?") }
    }

    private func card(_ ep: ModelEndpoint) -> some View {
        SettingsCard {
            HStack(spacing: 8) {
                Circle().fill((ep.online ?? true) ? theme.green : theme.secondaryText).frame(width: 8, height: 8)
                Text(ep.name).font(.ody(.subheadline).weight(.semibold)).foregroundStyle(theme.fg).lineLimit(1)
                Text(ep.isImage ? "IMAGEM" : (ep.isLocal ? "LOCAL" : "API"))
                    .font(.ody(size: 9))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(theme.accent.opacity(0.2), in: Capsule())
                    .foregroundStyle(theme.accent)
                Spacer()
            }
            if let url = ep.url, !url.isEmpty {
                Text(url).font(.ody(size: 10)).foregroundStyle(theme.secondaryText).lineLimit(1)
            }
            HStack {
                // Two whole sentences, not one with an interpolated tail: the
                // interpolated form produces a key ("%lld modelo(s)%@") no
                // locale has, so it always rendered in Portuguese.
                // visible/total: an endpoint whose models are all hidden used
                // to read "Modelos: 0" and tell the user to re-probe it.
                Group {
                    if ep.isEnabled { Text("Modelos: \(ep.models.count)/\(ep.total) · ativo") }
                    else { Text("Modelos: \(ep.models.count)/\(ep.total) · desativado") }
                }
                .font(.ody(size: 11))
                .foregroundStyle(ep.isEnabled ? theme.green : theme.secondaryText)
                Spacer()
                if vm.refreshing == ep.id {
                    ProgressView().controlSize(.small).tint(theme.accent)
                } else {
                    Button("Atualizar") { Task { await vm.refresh(ep) } }
                        .buttonStyle(.plain).foregroundStyle(theme.fg)
                }
                Button(ep.isEnabled ? "Desativar" : "Ativar") { Task { await vm.toggle(ep) } }
                    .buttonStyle(.plain).foregroundStyle(theme.fg)
                // Deleting an endpoint also resets every default that pointed
                // at it (chat, utility, vision, research models, fallbacks),
                // so ask first — except for one that is already offline, where
                // the web skips the question too.
                Button("Remover", role: .destructive) {
                    if ep.online == false { Task { await vm.delete(ep) } } else { removing = ep }
                }
                .buttonStyle(.plain).foregroundStyle(theme.danger)
            }
            .font(.ody(size: 12))
            .disabled(vm.refreshing != nil)
            // Its own row: the buttons above already fill an iPhone's width.
            Button { picking = ep } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.ody(size: 11))
                    Text("Escolher modelos").font(.ody(size: 12))
                    Spacer()
                    Image(systemName: "chevron.right").font(.ody(size: 10))
                }
                .foregroundStyle(theme.fg)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if ep.total == 0 {
                Text("Sem modelos em cache. Use Atualizar para sondar o endpoint.")
                    .font(.ody(size: 10))
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }
}

// MARK: - AI Defaults

struct Fallback: Identifiable { let id = UUID(); var endpointId: String; var model: String }

@MainActor final class AIDefaultsVM: ObservableObject {
    /// The two fallback chains the server still resolves. The editor 1.8
    /// shipped pointed at `default_model_fallbacks`, a key the server retired:
    /// it loaded empty and every edit flashed "Salvo" for a write thrown away.
    enum Chain: String, CaseIterable {
        case utility = "utility_model_fallbacks"
        case vision = "vision_model_fallbacks"
    }
    /// The web's `_vlExclude`: not a capability check, a blocklist of model
    /// ids that are obviously not vision models.
    static let notVision = ["audio", "realtime", "tts", "dall-e", "embedding", "search", "whisper"]
    static func isVisionModel(_ id: String) -> Bool {
        let l = id.lowercased()
        return !notVision.contains { l.contains($0) }
    }

    @Published var endpoints: [ModelEndpoint] = []
    @Published var chatEp = ""
    @Published var chatModel = ""
    @Published var chains: [Chain: [Fallback]] = [.utility: [], .vision: []]
    @Published var utilEp = ""
    @Published var utilModel = ""
    @Published var visionEnabled = true
    @Published var visionModel = ""
    @Published var researchEp = ""
    @Published var researchModel = ""
    @Published var status = ""
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func load() async {
        endpoints = (try? await api.modelEndpoints()) ?? []
        if let s = try? await api.getSettings() {
            chatEp = s.string("default_endpoint_id")
            chatModel = s.string("default_model")
            for c in Chain.allCases {
                chains[c] = s.fallbacks(c.rawValue).map { Fallback(endpointId: $0.endpointId, model: $0.model) }
            }
            utilEp = s.string("utility_endpoint_id")
            utilModel = s.string("utility_model")
            visionEnabled = s.bool("vision_enabled", default: true)
            visionModel = s.string("vision_model")
            researchEp = s.string("research_endpoint_id")
            researchModel = s.string("research_model")
        }
    }
    func models(_ epId: String) -> [String] { endpoints.first { $0.id == epId }?.models ?? [] }
    func name(_ epId: String) -> String { endpoints.first { $0.id == epId }?.name ?? "—" }
    var allModels: [String] {
        var seen = Set<String>(); var out: [String] = []
        for ep in endpoints where ep.isEnabled { for m in ep.models where !seen.contains(m) { seen.insert(m); out.append(m) } }
        return out
    }
    var enabledEndpoints: [ModelEndpoint] { endpoints.filter { $0.isEnabled } }

    func saveChat() async {
        do { try await api.saveSettings(["default_endpoint_id": chatEp, "default_model": chatModel]); flash("Salvo") }
        catch { flash("Falha") }
    }
    func saveUtil() async {
        do { try await api.saveSettings(["utility_endpoint_id": utilEp, "utility_model": utilModel]); flash("Salvo") }
        catch { flash("Falha") }
    }
    func saveVision() async {
        do { try await api.saveSettings(["vision_enabled": visionEnabled, "vision_model": visionModel]); flash("Salvo") }
        catch { flash("Falha") }
    }
    func saveResearch() async {
        do { try await api.saveSettings(["research_endpoint_id": researchEp, "research_model": researchModel]); flash("Salvo") }
        catch { flash("Falha") }
    }
    func addFallback(to c: Chain) {
        chains[c, default: []].append(Fallback(endpointId: enabledEndpoints.first?.id ?? "", model: ""))
    }
    func removeFallback(_ f: Fallback, from c: Chain) {
        chains[c]?.removeAll { $0.id == f.id }
        Task { await saveFallbacks(c) }
    }
    /// Each chain saves itself, as on the web — a half-filled row is skipped.
    func saveFallbacks(_ c: Chain) async {
        let clean = (chains[c] ?? []).filter { !$0.endpointId.isEmpty && !$0.model.isEmpty }
            .map { ["endpoint_id": $0.endpointId, "model": $0.model] }
        do { try await api.saveSettings([c.rawValue: clean]); flash("Salvo") }
        catch { flash("Falha") }
    }
    private func flash(_ s: String) { status = s; DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.status = "" } }
}

struct AIDefaultsSection: View {
    @StateObject private var vm: AIDefaultsVM
    @Environment(\.theme) private var theme
    init(app: AppState) { _vm = StateObject(wrappedValue: AIDefaultsVM(api: app.api)) }

    var body: some View {
        SettingsScroll("Padrões de IA", subtitle: "Modelos usados ao criar uma nova conversa e em tarefas de fundo.") {
            SettingsCard {
                Text("Modelo de chat padrão").font(.ody(.subheadline).weight(.semibold)).foregroundStyle(theme.fg)
                label("Endpoint")
                endpointMenu(selected: vm.chatEp, includeSame: false) { id in
                    vm.chatEp = id; vm.chatModel = vm.models(id).first ?? ""; Task { await vm.saveChat() }
                }
                label("Modelo")
                modelMenu(epId: vm.chatEp, selected: vm.chatModel) { m in vm.chatModel = m; Task { await vm.saveChat() } }
            }

            SettingsCard {
                Text("Modelo utilitário").font(.ody(.subheadline).weight(.semibold)).foregroundStyle(theme.fg)
                Text("Tarefas de fundo (compactação, nomear conversas, memórias). Vazio = usa o modelo de chat.")
                    .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                label("Endpoint")
                endpointMenu(selected: vm.utilEp, includeSame: true) { id in
                    vm.utilEp = id; vm.utilModel = id.isEmpty ? "" : (vm.models(id).first ?? ""); Task { await vm.saveUtil() }
                }
                if !vm.utilEp.isEmpty {
                    label("Modelo")
                    modelMenu(epId: vm.utilEp, selected: vm.utilModel) { m in vm.utilModel = m; Task { await vm.saveUtil() } }
                }
                fallbackRows(.utility)
            }

            SettingsCard {
                HStack {
                    Text("Visão").font(.ody(.subheadline).weight(.semibold)).foregroundStyle(theme.fg)
                    Spacer()
                    Toggle("", isOn: Binding(get: { vm.visionEnabled }, set: { vm.visionEnabled = $0; Task { await vm.saveVision() } }))
                        .labelsHidden().tint(theme.accent)
                }
                Text("Analisa imagens com um modelo com visão.")
                    .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                if vm.visionEnabled {
                    label("Modelo")
                    Menu {
                        Button("Auto-detectar") { vm.visionModel = ""; Task { await vm.saveVision() } }
                        ForEach(vm.allModels.filter(AIDefaultsVM.isVisionModel), id: \.self) { m in
                            Button(m) { vm.visionModel = m; Task { await vm.saveVision() } }
                        }
                    } label: { menuLabel(vm.visionModel.isEmpty ? "Auto-detectar" : vm.visionModel) }
                    fallbackRows(.vision)
                }
            }

            SettingsCard {
                Text("Pesquisa profunda").font(.ody(.subheadline).weight(.semibold)).foregroundStyle(theme.fg)
                label("Endpoint")
                endpointMenu(selected: vm.researchEp, includeSame: true) { id in
                    vm.researchEp = id; vm.researchModel = id.isEmpty ? "" : (vm.models(id).first ?? ""); Task { await vm.saveResearch() }
                }
                if !vm.researchEp.isEmpty {
                    label("Modelo")
                    modelMenu(epId: vm.researchEp, selected: vm.researchModel) { m in vm.researchModel = m; Task { await vm.saveResearch() } }
                }
            }

            if !vm.status.isEmpty {
                Text(LocalizedStringKey(vm.status)).font(.ody(size: 11)).foregroundStyle(theme.green)
            }
        }
        .task { await vm.load() }
    }

    private func label(_ s: String) -> some View {
        Text(LocalizedStringKey(s)).font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
    }

    /// One chain: endpoint + model per row, minus to drop, plus to add.
    /// The vision chain only offers models that pass the vision blocklist.
    @ViewBuilder
    private func fallbackRows(_ chain: AIDefaultsVM.Chain) -> some View {
        label("Fallbacks")
        ForEach(chainBinding(chain)) { fb in
            fallbackRow(fb, chain: chain)
        }
        Button { vm.addFallback(to: chain) } label: { Label("Adicionar fallback", systemImage: "plus") }
            .buttonStyle(.plain).font(.ody(size: 11)).foregroundStyle(theme.accent)
    }

    private func chainBinding(_ chain: AIDefaultsVM.Chain) -> Binding<[Fallback]> {
        Binding<[Fallback]>(get: { vm.chains[chain] ?? [] }, set: { vm.chains[chain] = $0 })
    }

    private func fallbackRow(_ fb: Binding<Fallback>, chain: AIDefaultsVM.Chain) -> some View {
        let filter: ((String) -> Bool)? = chain == .vision ? { AIDefaultsVM.isVisionModel($0) } : nil
        return HStack(spacing: 6) {
            endpointMenu(selected: fb.wrappedValue.endpointId, includeSame: false) { id in
                fb.wrappedValue.endpointId = id
                fb.wrappedValue.model = vm.models(id).first ?? ""
                Task { await vm.saveFallbacks(chain) }
            }
            modelMenu(epId: fb.wrappedValue.endpointId, selected: fb.wrappedValue.model, filter: filter) { m in
                fb.wrappedValue.model = m
                Task { await vm.saveFallbacks(chain) }
            }
            Button { vm.removeFallback(fb.wrappedValue, from: chain) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.plain).foregroundStyle(theme.secondaryText)
        }
    }

    private func endpointMenu(selected: String, includeSame: Bool, _ pick: @escaping (String) -> Void) -> some View {
        Menu {
            if includeSame { Button("Igual ao chat") { pick("") } }
            ForEach(vm.endpoints.filter { $0.isEnabled }) { ep in
                Button(ep.name) { pick(ep.id) }
            }
        } label: {
            menuLabel(selected.isEmpty ? (includeSame ? "Igual ao chat" : "Selecionar…") : vm.name(selected))
        }
    }
    private func modelMenu(epId: String, selected: String, filter: ((String) -> Bool)? = nil,
                           _ pick: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(vm.models(epId).filter { filter?($0) ?? true }, id: \.self) { m in Button(m) { pick(m) } }
        } label: {
            menuLabel(selected.isEmpty ? "Selecionar…" : selected)
        }
    }
    private func menuLabel(_ s: String) -> some View {
        HStack {
            Text(LocalizedStringKey(s)).font(.ody(.subheadline)).foregroundStyle(theme.fg).lineLimit(1)
            Spacer()
            Image(systemName: "chevron.up.chevron.down").font(.ody(size: 9)).foregroundStyle(theme.secondaryText)
        }
        .padding(10).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
}

// MARK: - Add models (connect a new endpoint)

@MainActor final class AddModelsVM: ObservableObject {
    @Published var name = ""
    @Published var baseURL = ""
    @Published var apiKey = ""
    @Published var kind = "local"     // "local" | "api"
    @Published var saving = false
    @Published var ok = false
    @Published var message: String?
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    var canAdd: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saving
    }

    func add() async {
        saving = true; message = nil; defer { saving = false }
        let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let nm = name.trimmingCharacters(in: .whitespaces).isEmpty ? hostName(url) : name
        do {
            let probe = try await api.createEndpoint(name: nm, baseURL: url,
                                                     apiKey: apiKey.isEmpty ? nil : apiKey, kind: kind)
            // Green only when the host answered. A dead URL used to read
            // "Adicionado" in green while the row it created was offline.
            ok = probe.isOnline
            message = probe.isOnline
                ? L("Conectado: %lld modelos.", probe.models.count)
                : L("Falha: %@", probe.pingError ?? "offline")
            if ok { name = ""; baseURL = ""; apiKey = "" }
        } catch {
            ok = false
            message = L("Falha: %@", SettingsUI.msg(error))
        }
    }

    private func hostName(_ s: String) -> String {
        guard let u = URL(string: s), let h = u.host else { return s }
        return u.port.map { "\(h):\($0)" } ?? h
    }
}

/// The two subscription providers the server connects through a device
/// flow. There is no status route: "connected" is an endpoint row whose
/// host matches, and "disconnect" is deleting that row.
enum DeviceProvider: String, CaseIterable, Identifiable {
    case copilot = "copilot"
    case chatgpt = "chatgpt-subscription"
    var id: String { rawValue }
    var title: String { self == .copilot ? "GitHub Copilot" : "ChatGPT Subscription" }
    var hostMatch: String { self == .copilot ? "githubcopilot.com" : "backend-api/codex" }
}

@MainActor final class DeviceFlowVM: ObservableObject {
    let provider: DeviceProvider
    @Published var start: DeviceFlowStart?
    @Published var connectedId: String?
    @Published var models = 0
    @Published var busy = false
    @Published var error: String?
    @Published var ok: String?
    private let api: APIClient
    private var task: Task<Void, Never>?
    init(api: APIClient, provider: DeviceProvider) { self.api = api; self.provider = provider }

    func loadStatus(_ endpoints: [ModelEndpoint]) {
        let ep = endpoints.first { ($0.url ?? "").contains(provider.hostMatch) }
        connectedId = ep?.id
        models = ep?.total ?? 0
    }

    func connect() {
        task?.cancel(); error = nil; ok = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let s = try await api.deviceFlowStart(provider.rawValue)
                start = s
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: UInt64(s.step * 1_000_000_000))
                    let p = try await api.deviceFlowPoll(provider.rawValue, pollId: s.pollId)
                    switch p.status {
                    case "authorized":
                        connectedId = p.endpoint?.id
                        models = p.endpoint?.models.count ?? 0
                        start = nil
                        ok = L("Conectado: %lld modelos.", models)
                        return
                    case "failed":
                        start = nil
                        error = p.error == "expired_token" ? L("A sessão de login expirou. Tente de novo.")
                                                            : L("Autorização recusada: %@", p.error ?? "")
                        return
                    default: continue
                    }
                }
            } catch is CancellationError {
            } catch {
                start = nil
                self.error = SettingsUI.failure(error, "Falha: %@", admin: "Só um administrador pode conectar provedores.")
            }
        }
    }

    func cancel() {
        task?.cancel(); task = nil
        if let s = start { Task { await api.deviceFlowCancel(provider.rawValue, pollId: s.pollId) } }
        start = nil
    }

    func disconnect() async {
        guard let id = connectedId else { return }
        busy = true; defer { busy = false }
        do { try await api.deleteEndpoint(id); connectedId = nil; models = 0; ok = nil }
        catch { self.error = SettingsUI.failure(error, "Falha: %@") }
    }
}

struct ProviderConnectCard: View {
    @StateObject private var vm: DeviceFlowVM
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    let endpoints: [ModelEndpoint]
    @State private var copied = false
    init(app: AppState, provider: DeviceProvider, endpoints: [ModelEndpoint]) {
        _vm = StateObject(wrappedValue: DeviceFlowVM(api: app.api, provider: provider))
        self.endpoints = endpoints
    }

    var body: some View {
        SettingsCard {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.key").foregroundStyle(theme.accent)
                Text(verbatim: vm.provider.title).font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
                Spacer()
                if vm.connectedId != nil {
                    Text("Conectado").font(.ody(size: 10)).foregroundStyle(theme.green)
                } else {
                    Text("Não conectado").font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                }
            }
            if let s = vm.start {
                Text("Entre na sua conta para liberar os modelos deste provedor.")
                    .font(.ody(size: 11)).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text(L("Código: %@", s.userCode)).font(.ody(size: 14).monospaced()).foregroundStyle(theme.fg).textSelection(.enabled)
                    Button {
                        Clipboard.copy(s.userCode); copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: { Label(copied ? "Código copiado" : "Copiar código", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.plain).font(.ody(size: 11)).foregroundStyle(theme.accent)
                }
                if let u = s.authURL {
                    Button { openURL(u) } label: { Label("Abrir página de autorização", systemImage: "safari") }
                        .buttonStyle(.plain).font(.ody(size: 12)).foregroundStyle(theme.accent)
                }
                HStack {
                    ProgressView().controlSize(.small).tint(theme.accent)
                    Text("Aguardando autorização…").font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
                    Spacer()
                    Button("Cancelar") { vm.cancel() }.buttonStyle(.plain).font(.ody(size: 12)).foregroundStyle(theme.secondaryText)
                }
            } else {
                if vm.connectedId != nil {
                    Text(L("Modelos: %lld", vm.models)).font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
                }
                if let e = vm.error { Text(LocalizedStringKey(e)).font(.ody(size: 11)).foregroundStyle(theme.danger) }
                if let o = vm.ok { Text(LocalizedStringKey(o)).font(.ody(size: 11)).foregroundStyle(theme.green) }
                HStack {
                    if vm.connectedId != nil {
                        Button("Desconectar", role: .destructive) { Task { await vm.disconnect() } }
                            .buttonStyle(.plain).font(.ody(size: 12)).foregroundStyle(theme.danger).disabled(vm.busy)
                    } else {
                        Button("Conectar") { vm.connect() }
                            .buttonStyle(.plain).font(.ody(size: 12)).foregroundStyle(theme.accent)
                    }
                    Spacer()
                }
            }
        }
        .onAppear { vm.loadStatus(endpoints) }
        .onChange(of: endpoints.map(\.id)) { _, _ in vm.loadStatus(endpoints) }
        .onDisappear { vm.cancel() }
    }
}

struct AddModelsSection: View {
    @StateObject private var vm: AddModelsVM
    @Environment(\.theme) private var theme
    @EnvironmentObject private var app: AppState
    private let host: AppState
    @State private var endpoints: [ModelEndpoint] = []
    init(app: AppState) { self.host = app; _vm = StateObject(wrappedValue: AddModelsVM(api: app.api)) }

    var body: some View {
        SettingsScroll("Adicionar modelos",
                       subtitle: "Conecte um endpoint local (Ollama, LM Studio…) ou uma API compatível com OpenAI.") {
            SettingsCard {
                HStack(spacing: 8) {
                    typeChip("Local", "local")
                    typeChip("API", "api")
                    typeChip("Imagem", "image")
                    Spacer()
                }
                label("Base URL")
                field($vm.baseURL, placeholder: vm.kind == "local" ? "http://localhost:11434/v1" : "https://api.openai.com/v1")
                label("Nome (opcional)")
                field($vm.name, placeholder: "vazio = usa o host da URL")
                label(vm.kind == "local" ? "API key (opcional)" : "API key")
                field($vm.apiKey, placeholder: "sk-…", secure: true)
                HStack(spacing: 8) {
                    if let m = vm.message {
                        Text(m).font(.ody(size: 11))
                            .foregroundStyle(vm.ok ? theme.green : theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button { Task { await vm.add() } } label: {
                        HStack(spacing: 6) {
                            if vm.saving { ProgressView().controlSize(.small) }
                            Text("Adicionar")
                        }
                        .font(.ody(.subheadline).weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(vm.canAdd ? theme.accent : theme.border, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain).disabled(!vm.canAdd)
                }
            }
            Text("O servidor sonda a Base URL e descobre os modelos sozinho. Depois, ative/desative em “Modelos conectados”.")
                .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
            if app.isAdmin {
                Text("Contas conectadas").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
                ForEach(DeviceProvider.allCases) { p in
                    ProviderConnectCard(app: host, provider: p, endpoints: endpoints)
                }
            }
        }
        .task { endpoints = (try? await host.api.modelEndpoints()) ?? [] }
    }

    private func typeChip(_ title: String, _ value: String) -> some View {
        Button { vm.kind = value; vm.message = nil } label: {
            Text(LocalizedStringKey(title)).font(.ody(size: 12))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .foregroundStyle(vm.kind == value ? .white : theme.secondaryText)
                .background(vm.kind == value ? theme.accent : theme.bg, in: Capsule())
                .overlay(Capsule().stroke(theme.border, lineWidth: vm.kind == value ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func label(_ s: String) -> some View {
        Text(LocalizedStringKey(s)).font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
    }

    @ViewBuilder private func field(_ bind: Binding<String>, placeholder: String, secure: Bool = false) -> some View {
        Group {
            if secure { SecureField(LocalizedStringKey(placeholder), text: bind) }
            else { TextField(LocalizedStringKey(placeholder), text: bind) }
        }
        .textFieldStyle(.plain).font(.ody(.subheadline)).foregroundStyle(theme.fg)
        .autocorrectionDisabled()
        .padding(10).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
}
