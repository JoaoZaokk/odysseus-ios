import SwiftUI

/// Settings › Aparência › Personalizar interface. Three cards — sidebar,
/// message field, conversation — one toggle per part of the screen, and a
/// per-card reset like the web's arrow-circle-back. A sheet on both
/// platforms: Aparência is a pane on macOS, where nothing can be pushed.
struct InterfaceSettingsView: View {
    @AppStorage(UIVisibility.storageKey) private var raw = ""
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var ui: UIVisibility { UIVisibility(raw: raw) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(UIVisibility.Group.allCases) { g in card(g) }
                    Text("Vale só para este aparelho, como na versão web.")
                        .font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Personalizar interface")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Concluído") { dismiss() } }
            }
            .themedNavBar(theme)
        }
        .tint(theme.accent)
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 600)
        #endif
    }

    private func card(_ g: UIVisibility.Group) -> some View {
        SettingsCard {
            HStack {
                Text(LocalizedStringKey(g.title)).font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
                Spacer()
                Button("Restaurar padrão") { var u = ui; u.reset(g); raw = u.raw }
                    .buttonStyle(.plain).font(.ody(size: 11)).foregroundStyle(theme.accent)
                    .disabled(UIVisibility.Key.allCases.filter { $0.group == g }.allSatisfy { ui.isOn($0) })
            }
            ForEach(UIVisibility.Key.allCases.filter { $0.group == g }) { k in
                Toggle(isOn: Binding(get: { ui.isOn(k) }, set: { on in var u = ui; u.set(k, on: on); raw = u.raw })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(k.title)).font(.ody(.subheadline)).foregroundStyle(theme.fg)
                        if let c = k.caption {
                            Text(LocalizedStringKey(c)).font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                        }
                    }
                }
                .tint(theme.accent)
                // Section rows follow the "Espaços" switch — greyed, not lost.
                .disabled(k.isSection && !ui.isOn(.spaces))
                .padding(.leading, k.isSection ? 14 : 0)
            }
        }
    }
}
