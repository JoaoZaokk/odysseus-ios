import SwiftUI

/// Per-user privileges (admin): the seven feature toggles, the daily
/// message limit and the allowed-model list — the substance of the web's
/// Users tab. One PUT with all eleven keys on Salvar; the reply's merged
/// dict replaces the row.
struct UserPrivilegesSheet: View {
    let user: AdminUser
    /// (model id, endpoint name) for every online endpoint's visible models.
    let catalog: [(id: String, endpoint: String)]
    var onSave: (UserPrivileges) async -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var p: UserPrivileges
    @State private var limitText: String
    @State private var allowed: Set<String>
    @State private var saving = false

    init(user: AdminUser, catalog: [(id: String, endpoint: String)], onSave: @escaping (UserPrivileges) async -> Void) {
        self.user = user; self.catalog = catalog; self.onSave = onSave
        _p = State(initialValue: user.privileges)
        _limitText = State(initialValue: user.privileges.maxMessagesPerDay == 0 ? "" : String(user.privileges.maxMessagesPerDay))
        _allowed = State(initialValue: Set(user.privileges.allowedModels))
    }

    private var modelIDs: [String] { catalog.map(\.id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsCard {
                        Text("Recursos").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
                        toggle("Modo agente", $p.canUseAgent)
                        toggle("Automação de navegador", $p.canUseBrowser)
                        toggle("Shell / Python / Arquivos", $p.canUseBash)
                        toggle("Editor de documentos", $p.canUseDocuments)
                        toggle("Pesquisa profunda", $p.canUseResearch)
                        toggle("Geração de imagens", $p.canGenerateImages)
                        toggle("Memória e skills", $p.canManageMemory)
                    }
                    SettingsCard {
                        Text("Limites").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
                        SettingsUI.field("Limite diário de mensagens", $limitText, placeholder: "0", theme: theme, numeric: true)
                        Text("0 = sem limite").font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                    }
                    SettingsCard {
                        Text("Modelos permitidos").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
                        Text(summary).font(.ody(size: 11)).foregroundStyle(p.blockAllModels ? theme.danger : theme.secondaryText)
                        HStack(spacing: 14) {
                            Button("Todos") { allowed = []; p.blockAllModels = false }
                                .buttonStyle(.plain).foregroundStyle(theme.accent)
                            Button("Nenhum") { allowed = []; p.blockAllModels = true }
                                .buttonStyle(.plain).foregroundStyle(theme.danger)
                            Spacer()
                        }
                        .font(.ody(size: 12))
                        if modelIDs.isEmpty {
                            Text("Nenhum modelo disponível.").font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
                        } else {
                            FlowChips(items: modelIDs, selected: Binding(
                                get: { allowed },
                                set: { allowed = $0; if !$0.isEmpty { p.blockAllModels = false } }), theme: theme)
                        }
                    }
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle(user.username)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView().controlSize(.small) }
                    else { Button("Salvar") { Task { await save() } } }
                }
            }
            .themedNavBar(theme)
        }
        .tint(theme.accent)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    private var summary: String {
        if p.blockAllModels { return L("Nenhum modelo permitido") }
        if allowed.isEmpty { return L("Todos os modelos permitidos (sem restrição)") }
        return L("%lld modelo(s) permitido(s)", allowed.count)
    }

    private func toggle(_ label: String, _ bind: Binding<Bool>) -> some View {
        Toggle(isOn: bind) { Text(LocalizedStringKey(label)).font(.ody(.subheadline)).foregroundStyle(theme.fg) }
            .tint(theme.accent)
    }

    private func save() async {
        saving = true; defer { saving = false }
        var out = p
        out.maxMessagesPerDay = max(0, Int(limitText) ?? 0)
        out.allowedModels = Array(allowed).sorted()
        out.allowedModelsRestricted = !allowed.isEmpty
        await onSave(out)
        dismiss()
    }
}
