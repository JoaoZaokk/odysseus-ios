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
    #if os(iOS)
    @AppStorage(AppIconManager.storageKey) private var appIcon = AppIcon.odysseus.rawValue
    #endif

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        grid
            .odyNavTitle("Tema", parent: "Aparência")
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
            .padding(.horizontal, Spacing.gutter)
            .padding(.top, 16)
            .padding(.bottom, Spacing.bottomBreathing)
        }
    }

    /// A horizontal strip that says it scrolls: it bleeds to the screen's
    /// edges, starts on the gutter, ends with room to spare and fades out on
    /// the right. Cut flush at the border ("Anthropic S…", "Pétala") it read
    /// as a layout bug, not as more to the right.
    private func carousel<C: View>(spacing: CGFloat, @ViewBuilder _ content: () -> C) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) { content() }
                .padding(.leading, Spacing.gutter)
                .padding(.trailing, Spacing.gutter + 36)
                .padding(.vertical, 2)
        }
        .padding(.horizontal, -Spacing.gutter)
        .trailingFade()
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
                carousel(spacing: 8) {
                    ForEach(AppFontFamily.allCases) { f in
                        chip(f.label, selected: themes.fontFamily == f, labelFont: fontPreview(f)) {
                            themes.selectFont(f)
                        }
                    }
                }
            }
            // Transparency and "Customize UI" under their own label, in one
            // card — they floated between FONTE and ÍCONE in a bigger body
            // than the labels around them.
            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("Interface")
                VStack(spacing: 0) {
                    Toggle(isOn: Binding(get: { themes.transparency }, set: { themes.transparency = $0 })) {
                        Text("Transparência")
                            .font(.ody(.subheadline))
                            .foregroundStyle(theme.fg)
                    }
                    .tint(theme.accent)
                    .frame(minHeight: Spacing.tapTarget)
                    Rectangle().fill(theme.border).frame(height: 1)
                    customizeRow
                        .padding(.vertical, 10)
                }
                .padding(.horizontal, 14)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))
            }
            // Home-screen icon. iOS only — macOS has no alternate app icons.
            #if os(iOS)
            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("Ícone")
                carousel(spacing: 10) {
                    ForEach(AppIcon.allCases) { iconChoice($0) }
                }
            }
            #endif
            // Animated background
            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("Fundo animado")
                carousel(spacing: 8) {
                    ForEach(BackgroundPattern.allCases) { p in
                        chip(p.label, selected: themes.background == p) {
                            themes.background = p
                        }
                    }
                }
            }
        }
    }

    /// The web's "Customize UI" checkboxes, for the parts this app has.
    private var customizeRow: some View {
        Button { customizing = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Personalizar interface").font(.ody(.subheadline)).foregroundStyle(theme.fg)
                    Text(UIVisibility(raw: uiRaw).isDefault
                         ? "Mostre ou esconda partes da barra lateral, do campo de mensagem e da conversa."
                         : "Alguns itens estão escondidos.")
                        .font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    #if os(iOS)
    /// One home-screen icon. The preview reads the same PNG the system uses, so
    /// what is on the strip is what lands on the home screen.
    @ViewBuilder
    private func iconChoice(_ icon: AppIcon) -> some View {
        let active = appIcon == icon.rawValue
        Button {
            AppIconManager.select(icon)
        } label: {
            VStack(spacing: 5) {
                Group {
                    if let ui = UIImage(named: icon.previewImageName) {
                        Image(uiImage: ui).resizable()
                    } else {
                        // Never in a correct build: the file is a bundled resource.
                        RoundedRectangle(cornerRadius: 13, style: .continuous).fill(theme.panel)
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(active ? theme.accent : theme.border, lineWidth: active ? 2.5 : 1))
                Text(icon.label)
                    .font(.ody(size: 10))
                    .foregroundStyle(active ? theme.fg : theme.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }
    #endif

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
            Text(verbatim: "mimo-v2.6-pro")
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
