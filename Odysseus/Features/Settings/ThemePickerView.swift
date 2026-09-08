import SwiftUI

/// Theme gallery — mirrors the web app's "Theme" panel. A grid of live-preview
/// swatches; tapping one switches the whole app instantly (and persists it).
///
/// Reached from Settings › Aparência only (pushed on iOS, a pane in the macOS
/// drawer). The sidebar "Tema" shortcut that also presented it as a sheet was
/// removed in 1.9 — it was the third row above the conversation list.
struct ThemePickerView: View {

    @EnvironmentObject private var themes: ThemeStore
    @Environment(\.theme) private var theme
    @State private var customizing = false
    @AppStorage(UIVisibility.storageKey) private var uiRaw = ""

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        grid
            .navigationTitle("Tema")
            .navigationBarTitleDisplayMode(.inline)
            .background(theme.bg)
            .sheet(isPresented: $customizing) { InterfaceSettingsView().environmentObject(themes) }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 460)
        #endif
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                controls
                sectionLabel("Temas")
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Theme.all) { t in
                        swatch(t)
                    }
                }
            }
            .padding(16)
        }
    }

    private func sectionLabel(_ s: String) -> some View {
        // Localize THEN uppercase: `s.uppercased()` would hand Text a plain String
        // (verbatim, no lookup), leaking the PT base literal in other languages.
        Text(LocalizedStringKey(s))
            .textCase(.uppercase)
            .font(.ody(.caption))
            .foregroundStyle(theme.secondaryText)
    }

    // MARK: - Appearance controls (font / transparency / animated background)

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Font family
            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("Fonte")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AppFontFamily.allCases) { f in
                            chip(f.label, selected: themes.fontFamily == f, labelFont: fontPreview(f)) {
                                themes.selectFont(f)
                            }
                        }
                    }
                }
            }
            // Transparency
            Toggle(isOn: Binding(get: { themes.transparency }, set: { themes.transparency = $0 })) {
                Text("Transparência")
                    .font(.ody(.subheadline))
                    .foregroundStyle(theme.fg)
            }
            .tint(theme.accent)
            // The web's "Customize UI" checkboxes, for the parts this app has.
            Button { customizing = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Personalizar interface").font(.ody(.subheadline)).foregroundStyle(theme.fg)
                        Text(UIVisibility(raw: uiRaw).isDefault
                             ? "Mostre ou esconda partes da barra lateral, do campo de mensagem e da conversa."
                             : "Alguns itens estão escondidos.")
                            .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Animated background
            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("Fundo animado")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(BackgroundPattern.allCases) { p in
                            chip(p.label, selected: themes.background == p) {
                                themes.background = p
                            }
                        }
                    }
                }
            }
        }
    }

    private func fontPreview(_ f: AppFontFamily) -> Font {
        if let name = f.customName { return .custom(name, size: 13) }
        return .system(.subheadline, design: f.design)
    }

    private func chip(_ label: String, selected: Bool, labelFont: Font? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(label))
                .font(labelFont ?? .ody(size: 12))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(selected ? .white : theme.secondaryText)
                .background(selected ? theme.accent : theme.panel, in: Capsule())
                .overlay(Capsule().stroke(theme.border, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func swatch(_ t: Theme) -> some View {
        let active = t.id == themes.theme.id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { themes.select(t) }
        } label: {
            VStack(spacing: 7) {
                preview(t)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(active ? theme.accent : theme.border,
                                    lineWidth: active ? 2.5 : 1)
                    )
                HStack(spacing: 5) {
                    if active {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.ody(size: 12))
                            .foregroundStyle(theme.accent)
                    }
                    Text(t.name)
                        .font(.ody(size: 12))
                        .foregroundStyle(theme.fg)
                    Spacer()
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// A miniature of the chat UI rendered in theme `t` — recognizable at a glance.
    private func preview(_ t: Theme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                BrandMark(size: 16)
                Text("Odysseus")
                    .font(.ody(size: 11, weight: .semibold))
                    .foregroundStyle(t.accent)
                Spacer(minLength: 0)
            }
            Text("Como posso ajudar?")
                .font(.ody(size: 10))
                .foregroundStyle(t.fg)
                .lineLimit(1)
            Text("mimo-v2.5-pro")
                .font(.ody(size: 8))
                .foregroundStyle(t.green)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 5).fill(t.panel)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(t.border, lineWidth: 1))
                    .frame(width: 38, height: 13)
                Capsule().fill(t.accent).frame(width: 24, height: 13)
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(height: 104, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.bg)
        .environment(\.theme, t)   // so the embedded BrandMark uses this theme
    }
}
