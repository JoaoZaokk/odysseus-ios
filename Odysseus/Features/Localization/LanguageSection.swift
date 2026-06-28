import SwiftUI

/// Ajustes › Idioma — the in-app language picker. Offers an **Automatic** option
/// (follows the phone's native language) plus a manual override for each shipped
/// language. Switching applies live: `Bundle.main` is re-pointed and the root
/// view re-renders (it briefly returns to the home screen).
struct LanguageSection: View {
    @EnvironmentObject private var loc: LocalizationManager
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsScroll("Idioma", subtitle: "Selecione o idioma do aplicativo.") {
            SettingsCard {
                autoRow
                Divider().overlay(theme.border)
                ForEach(AppLanguage.allCases) { lang in
                    if lang != AppLanguage.allCases.first { Divider().overlay(theme.border) }
                    row(lang)
                }
            }

            Text("Por padrão, o app segue o idioma do seu aparelho. Ao trocar, ele volta para a tela inicial.")
                .font(.ody(size: 11, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Automatic (follow device) row.
    private var autoRow: some View {
        Button { loc.use(nil) } label: {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.ody(size: 18))
                    .foregroundStyle(theme.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automático (idioma do dispositivo)")
                        .font(.ody(.subheadline, design: .monospaced))
                        .foregroundStyle(theme.fg)
                    Text("Detectado: \(loc.detected.flag) \(loc.detected.nativeName)")
                        .font(.ody(size: 10, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer()
                if loc.isAutomatic {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ lang: AppLanguage) -> some View {
        let isSelected = (loc.selection == lang)
        return Button { loc.use(lang) } label: {
            HStack(spacing: 12) {
                Text(lang.flag).font(.ody(size: 20)).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.nativeName)
                        .font(.ody(.subheadline, design: .monospaced))
                        .foregroundStyle(theme.fg)
                    Text(lang.englishName)
                        .font(.ody(size: 10, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
