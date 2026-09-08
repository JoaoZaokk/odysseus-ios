import SwiftUI

#if os(macOS)
/// Read-only: the fixed Mac shortcuts, from the same table that binds them.
struct ShortcutsSection: View {
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsScroll("Atalhos", subtitle: "Atalhos fixos do teclado no Mac. Não são editáveis.") {
            ForEach(OdyShortcuts.groups, id: \.0) { group in
                SettingsCard {
                    Text(LocalizedStringKey(group.0)).font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
                    ForEach(group.1) { s in
                        HStack {
                            Text(LocalizedStringKey(s.label)).font(.ody(.subheadline)).foregroundStyle(theme.fg)
                            Spacer()
                            HStack(spacing: 4) {
                                ForEach(s.caps, id: \.self) { cap in
                                    Text(cap).font(.ody(size: 11)).foregroundStyle(theme.fg)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(theme.panel, in: RoundedRectangle(cornerRadius: 4))
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.border, lineWidth: 1))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
