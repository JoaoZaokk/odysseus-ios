import SwiftUI

/// Per-model visibility for one connected endpoint.
///
/// `GET /api/model-endpoints/{id}/models` returns every model the server has
/// discovered plus its state; `PATCH` on the same path rewrites it. Both are
/// admin-only, so a non-admin gets a 403 and an explanatory line instead of a
/// broken screen.
@MainActor final class EndpointModelsVM: ObservableObject {
    @Published var models: [EndpointModel] = []
    @Published var visible: Set<String> = []
    @Published var query = ""
    @Published var loading = false
    @Published var saving = false
    @Published var error: String?
    @Published var saved = false

    let endpoint: ModelEndpoint
    private let api: APIClient

    init(api: APIClient, endpoint: ModelEndpoint) {
        self.api = api
        self.endpoint = endpoint
    }

    /// Cloud APIs are allow-lists, local servers are deny-lists. The server
    /// reports the same value on every row; an empty list can't tell us, and
    /// the deny-list default matches what older servers do.
    var pinning: Bool { models.first?.pickerRequiresPinning ?? false }

    var filtered: [EndpointModel] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return models }
        return models.filter { $0.id.lowercased().contains(q) || $0.display.lowercased().contains(q) }
    }

    var dirty: Bool { visible != Set(models.filter(\.isVisible).map(\.id)) }

    func load() async {
        loading = true; defer { loading = false }
        do {
            let list = try await api.endpointModels(endpoint.id)
            models = list
            visible = Set(list.filter(\.isVisible).map(\.id))
            error = nil
        } catch let e where e.isCancellation {
        } catch APIError.http(403, _) {
            error = "Só um administrador pode escolher quais modelos aparecem."
        } catch {
            self.error = L("Não foi possível carregar os modelos: %@", SettingsUI.msg(error))
        }
    }

    func toggle(_ m: EndpointModel) {
        if visible.contains(m.id) { visible.remove(m.id) } else { visible.insert(m.id) }
        saved = false
    }

    /// Applies to the filtered rows only, so a search narrows what "all" means.
    func setAll(_ on: Bool) {
        for m in filtered { if on { visible.insert(m.id) } else { visible.remove(m.id) } }
        saved = false
    }

    func save() async {
        saving = true; defer { saving = false }
        let visibleIDs = models.map(\.id).filter { visible.contains($0) }
        let hiddenIDs = models.map(\.id).filter { !visible.contains($0) }
        do {
            try await api.setEndpointModelVisibility(endpoint.id, visible: visibleIDs,
                                                     hidden: hiddenIDs, pinning: pinning)
            await load()
            error = nil
            saved = true
        } catch APIError.http(403, _) {
            error = "Só um administrador pode escolher quais modelos aparecem."
        } catch {
            self.error = L("Não foi possível salvar: %@", SettingsUI.msg(error))
        }
    }

}

struct EndpointModelsView: View {
    @StateObject private var vm: EndpointModelsVM
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    init(app: AppState, endpoint: ModelEndpoint) {
        _vm = StateObject(wrappedValue: EndpointModelsVM(api: app.api, endpoint: endpoint))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.bg.ignoresSafeArea()
                VStack(spacing: 12) {
                    header
                    if vm.loading && vm.models.isEmpty {
                        Spacer(); ProgressView().tint(theme.accent); Spacer()
                    } else if vm.models.isEmpty {
                        Spacer()
                        Text("Nenhum modelo em cache. Use “Atualizar” na lista de endpoints para sondar.")
                            .font(.ody(size: 12))
                            .foregroundStyle(theme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Spacer()
                    } else {
                        list
                    }
                }
                .padding(.top, 14)
            }
            // The endpoint's own name — user data, shown verbatim.
            .navigationTitle(vm.endpoint.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.saving { ProgressView().controlSize(.small) }
                    else { Button("Salvar") { Task { await vm.save() } }.disabled(!vm.dirty) }
                }
            }
        }
        .tint(theme.accent)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
        .task { await vm.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if vm.pinning {
                    Text("Marque os modelos que devem aparecer no seletor. Nesta API, só os marcados ficam disponíveis.")
                } else {
                    Text("Desmarque os modelos que não quer ver no seletor.")
                }
            }
            .font(.ody(size: 11))
            .foregroundStyle(theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            if let e = vm.error {
                Text(LocalizedStringKey(e))
                    .font(.ody(size: 11)).foregroundStyle(theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            } else if vm.saved {
                Text("Salvo").font(.ody(size: 11)).foregroundStyle(theme.green)
            }

            if !vm.models.isEmpty {
                HStack(spacing: 8) {
                    TextField("Filtrar…", text: $vm.query)
                        .textFieldStyle(.plain)
                        .font(.ody(size: 12)).foregroundStyle(theme.fg)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(8)
                        .background(theme.panel, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                    Button("Todos") { vm.setAll(true) }
                    Button("Nenhum") { vm.setAll(false) }
                }
                .font(.ody(size: 12))
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)

                Text("\(vm.visible.count)/\(vm.models.count) visíveis")
                    .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.filtered) { m in
                    Button { vm.toggle(m) } label: { row(m) }
                        .buttonStyle(.plain)
                    Divider().overlay(theme.border)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
    }

    private func row(_ m: EndpointModel) -> some View {
        let on = vm.visible.contains(m.id)
        return HStack(spacing: 10) {
            Image(systemName: on ? "checkmark.square.fill" : "square")
                .font(.ody(size: 15))
                .foregroundStyle(on ? theme.accent : theme.secondaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.display)
                    .font(.ody(size: 13))
                    .foregroundStyle(on ? theme.fg : theme.secondaryText)
                    .lineLimit(1)
                if m.display != m.id {
                    Text(m.id)
                        .font(.ody(size: 10))
                        .foregroundStyle(theme.secondaryText).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
