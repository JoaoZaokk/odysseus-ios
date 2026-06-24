import SwiftUI

// MARK: - Added Models (connected endpoints)

@MainActor final class AddedModelsVM: ObservableObject {
    @Published var endpoints: [ModelEndpoint] = []
    @Published var loading = false
    @Published var error: String?
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func load() async {
        loading = true; defer { loading = false }
        do { endpoints = try await api.modelEndpoints(); self.error = nil }
        catch is CancellationError {}
        catch { self.error = msg(error) }
    }
    func toggle(_ ep: ModelEndpoint) async {
        do { try await api.setEndpointEnabled(ep.id, !ep.isEnabled); await load() }
        catch { self.error = "Não foi possível alterar: \(msg(error))" }
    }
    func delete(_ ep: ModelEndpoint) async {
        do { try await api.deleteEndpoint(ep.id); await load() }
        catch { self.error = "Não foi possível remover: \(msg(error))" }
    }
    private func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? e.localizedDescription }
}

struct AddedModelsSection: View {
    @StateObject private var vm: AddedModelsVM
    @Environment(\.theme) private var theme
    init(app: AppState) { _vm = StateObject(wrappedValue: AddedModelsVM(api: app.api)) }

    var body: some View {
        SettingsScroll("Modelos conectados", subtitle: "Endpoints que você conectou. Ative, desative ou remova.") {
            if vm.loading && vm.endpoints.isEmpty {
                ProgressView().tint(theme.accent)
            }
            if let e = vm.error {
                Text(e).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.accent)
            }
            ForEach(vm.endpoints) { ep in card(ep) }
            if vm.endpoints.isEmpty && !vm.loading {
                Text("Nenhum endpoint conectado.").font(.ody(size: 12, design: .monospaced)).foregroundStyle(theme.secondaryText)
            }
        }
        .task { await vm.load() }
    }

    private func card(_ ep: ModelEndpoint) -> some View {
        SettingsCard {
            HStack(spacing: 8) {
                Circle().fill((ep.online ?? true) ? theme.green : theme.secondaryText).frame(width: 8, height: 8)
                Text(ep.name).font(.ody(.subheadline, design: .monospaced).weight(.semibold)).foregroundStyle(theme.fg).lineLimit(1)
                Text(ep.isLocal ? "LOCAL" : "API")
                    .font(.ody(size: 9, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(theme.accent.opacity(0.2), in: Capsule())
                    .foregroundStyle(theme.accent)
                Spacer()
            }
            if let url = ep.url, !url.isEmpty {
                Text(url).font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText).lineLimit(1)
            }
            HStack {
                Text("\(ep.models.count) modelo(s)\(ep.isEnabled ? " · ativo" : " · desativado")")
                    .font(.ody(size: 11, design: .monospaced))
                    .foregroundStyle(ep.isEnabled ? theme.green : theme.secondaryText)
                Spacer()
                Button(ep.isEnabled ? "Desativar" : "Ativar") { Task { await vm.toggle(ep) } }
                    .buttonStyle(.plain).foregroundStyle(theme.fg)
                Button("Remover", role: .destructive) { Task { await vm.delete(ep) } }
                    .buttonStyle(.plain).foregroundStyle(theme.accent)
            }
            .font(.ody(size: 12, design: .monospaced))
        }
    }
}

// MARK: - AI Defaults

struct Fallback: Identifiable { let id = UUID(); var endpointId: String; var model: String }

@MainActor final class AIDefaultsVM: ObservableObject {
    @Published var endpoints: [ModelEndpoint] = []
    @Published var chatEp = ""
    @Published var chatModel = ""
    @Published var fallbacks: [Fallback] = []
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
            fallbacks = s.fallbacks("default_model_fallbacks").map { Fallback(endpointId: $0.endpointId, model: $0.model) }
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
    func addFallback() {
        fallbacks.append(Fallback(endpointId: enabledEndpoints.first?.id ?? "", model: ""))
    }
    func removeFallback(_ f: Fallback) {
        fallbacks.removeAll { $0.id == f.id }
        Task { await saveFallbacks() }
    }
    func saveFallbacks() async {
        let clean = fallbacks.filter { !$0.endpointId.isEmpty && !$0.model.isEmpty }
            .map { ["endpoint_id": $0.endpointId, "model": $0.model] }
        do { try await api.saveSettings(["default_model_fallbacks": clean]); flash("Salvo") }
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
                Text("Modelo de chat padrão").font(.ody(.subheadline, design: .monospaced).weight(.semibold)).foregroundStyle(theme.fg)
                label("Endpoint")
                endpointMenu(selected: vm.chatEp, includeSame: false) { id in
                    vm.chatEp = id; vm.chatModel = vm.models(id).first ?? ""; Task { await vm.saveChat() }
                }
                label("Modelo")
                modelMenu(epId: vm.chatEp, selected: vm.chatModel) { m in vm.chatModel = m; Task { await vm.saveChat() } }

                label("Fallbacks")
                ForEach($vm.fallbacks) { $fb in
                    HStack(spacing: 6) {
                        endpointMenu(selected: fb.endpointId, includeSame: false) { id in
                            fb.endpointId = id; fb.model = vm.models(id).first ?? ""; Task { await vm.saveFallbacks() }
                        }
                        modelMenu(epId: fb.endpointId, selected: fb.model) { m in fb.model = m; Task { await vm.saveFallbacks() } }
                        Button { vm.removeFallback(fb) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain).foregroundStyle(theme.secondaryText)
                    }
                }
                Button { vm.addFallback() } label: { Label("Adicionar fallback", systemImage: "plus") }
                    .buttonStyle(.plain).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.accent)
            }

            SettingsCard {
                Text("Modelo utilitário").font(.ody(.subheadline, design: .monospaced).weight(.semibold)).foregroundStyle(theme.fg)
                Text("Tarefas de fundo (compactação, nomear conversas, memórias). Vazio = usa o modelo de chat.")
                    .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                label("Endpoint")
                endpointMenu(selected: vm.utilEp, includeSame: true) { id in
                    vm.utilEp = id; vm.utilModel = id.isEmpty ? "" : (vm.models(id).first ?? ""); Task { await vm.saveUtil() }
                }
                if !vm.utilEp.isEmpty {
                    label("Modelo")
                    modelMenu(epId: vm.utilEp, selected: vm.utilModel) { m in vm.utilModel = m; Task { await vm.saveUtil() } }
                }
            }

            SettingsCard {
                HStack {
                    Text("Visão").font(.ody(.subheadline, design: .monospaced).weight(.semibold)).foregroundStyle(theme.fg)
                    Spacer()
                    Toggle("", isOn: Binding(get: { vm.visionEnabled }, set: { vm.visionEnabled = $0; Task { await vm.saveVision() } }))
                        .labelsHidden().tint(theme.accent)
                }
                Text("Analisa imagens com um modelo com visão.")
                    .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                if vm.visionEnabled {
                    label("Modelo")
                    Menu {
                        Button("Auto-detectar") { vm.visionModel = ""; Task { await vm.saveVision() } }
                        ForEach(vm.allModels, id: \.self) { m in Button(m) { vm.visionModel = m; Task { await vm.saveVision() } } }
                    } label: { menuLabel(vm.visionModel.isEmpty ? "Auto-detectar" : vm.visionModel) }
                }
            }

            SettingsCard {
                Text("Pesquisa profunda").font(.ody(.subheadline, design: .monospaced).weight(.semibold)).foregroundStyle(theme.fg)
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
                Text(vm.status).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.green)
            }
        }
        .task { await vm.load() }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
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
    private func modelMenu(epId: String, selected: String, _ pick: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(vm.models(epId), id: \.self) { m in Button(m) { pick(m) } }
        } label: {
            menuLabel(selected.isEmpty ? "Selecionar…" : selected)
        }
    }
    private func menuLabel(_ s: String) -> some View {
        HStack {
            Text(s).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg).lineLimit(1)
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
            try await api.createEndpoint(name: nm, baseURL: url,
                                         apiKey: apiKey.isEmpty ? nil : apiKey, kind: kind)
            ok = true
            message = "Adicionado. O servidor vai sondar a URL e listar os modelos."
            name = ""; baseURL = ""; apiKey = ""
        } catch {
            ok = false
            message = "Falha: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    private func hostName(_ s: String) -> String {
        guard let u = URL(string: s), let h = u.host else { return s }
        return u.port.map { "\(h):\($0)" } ?? h
    }
}

struct AddModelsSection: View {
    @StateObject private var vm: AddModelsVM
    @Environment(\.theme) private var theme
    init(app: AppState) { _vm = StateObject(wrappedValue: AddModelsVM(api: app.api)) }

    var body: some View {
        SettingsScroll("Adicionar modelos",
                       subtitle: "Conecte um endpoint local (Ollama, LM Studio…) ou uma API compatível com OpenAI.") {
            SettingsCard {
                HStack(spacing: 8) {
                    typeChip("Local", "local")
                    typeChip("API", "api")
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
                        Text(m).font(.ody(size: 11, design: .monospaced))
                            .foregroundStyle(vm.ok ? theme.green : theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button { Task { await vm.add() } } label: {
                        HStack(spacing: 6) {
                            if vm.saving { ProgressView().controlSize(.small) }
                            Text("Adicionar")
                        }
                        .font(.ody(.subheadline, design: .monospaced).weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(vm.canAdd ? theme.accent : theme.border, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain).disabled(!vm.canAdd)
                }
            }
            Text("O servidor sonda a Base URL e descobre os modelos sozinho. Depois, ative/desative em “Modelos conectados”.")
                .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
        }
    }

    private func typeChip(_ title: String, _ value: String) -> some View {
        Button { vm.kind = value; vm.message = nil } label: {
            Text(title).font(.ody(size: 12, design: .monospaced))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .foregroundStyle(vm.kind == value ? .white : theme.secondaryText)
                .background(vm.kind == value ? theme.accent : theme.bg, in: Capsule())
                .overlay(Capsule().stroke(theme.border, lineWidth: vm.kind == value ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
    }

    @ViewBuilder private func field(_ bind: Binding<String>, placeholder: String, secure: Bool = false) -> some View {
        Group {
            if secure { SecureField(placeholder, text: bind) } else { TextField(placeholder, text: bind) }
        }
        .textFieldStyle(.plain).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
        .autocorrectionDisabled()
        .padding(10).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
}
