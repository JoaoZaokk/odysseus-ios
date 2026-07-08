import SwiftUI

// Native, sectioned Settings panel — same structure/behavior as the Odysseus web
// "Settings" modal (sidebar of sections + content), built entirely in SwiftUI
// (no WebView). macOS = two-pane; iOS = list that pushes to the section.

enum SettingsSection: String, CaseIterable, Identifiable {
    case addModels, addedModels, aiDefaults, search
    case integrations, email, reminders, imageGen
    case appearance, language, account, server
    case agentTools, users, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addModels: return "Adicionar modelos"
        case .addedModels: return "Modelos conectados"
        case .aiDefaults: return "Padrões de IA"
        case .search: return "Busca"
        case .integrations: return "Integrações"
        case .email: return "Email"
        case .reminders: return "Lembretes"
        case .imageGen: return "Geração de imagem"
        case .appearance: return "Aparência"
        case .language: return "Idioma"
        case .account: return "Conta"
        case .server: return "Servidor"
        case .agentTools: return "Agent Tools"
        case .users: return "Usuários"
        case .system: return "Sistema"
        }
    }

    var icon: String {
        switch self {
        case .addModels: return "plus.rectangle.on.rectangle"
        case .addedModels: return "checkmark.seal"
        case .aiDefaults: return "brain"
        case .search: return "magnifyingglass"
        case .integrations: return "link"
        case .email: return "envelope"
        case .reminders: return "bell"
        case .imageGen: return "photo.on.rectangle.angled"
        case .appearance: return "paintpalette"
        case .language: return "globe"
        case .account: return "person.crop.circle"
        case .server: return "server.rack"
        case .agentTools: return "wrench.and.screwdriver"
        case .users: return "person.2"
        case .system: return "gearshape.2"
        }
    }

    /// Implemented natively this round. Others show a placeholder pointing to web.
    var implemented: Bool {
        switch self {
        case .addedModels, .aiDefaults, .search, .email, .imageGen, .appearance, .language, .account, .server:
            return true
        default:
            return false
        }
    }

    static let groups: [(String?, [SettingsSection])] = [
        (nil, [.addModels, .addedModels, .aiDefaults, .search]),
        (nil, [.integrations, .email, .reminders, .imageGen]),
        (nil, [.appearance, .language, .account, .server]),
        ("ADMIN", [.agentTools, .users, .system]),
    ]
}

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var themes: ThemeStore
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var selection: SettingsSection = .aiDefaults
    /// When presented as the macOS right-side drawer, the host passes a close
    /// action (there's no sheet to `dismiss`). nil → falls back to `dismiss()`.
    var onClose: (() -> Void)? = nil

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.border)
            HStack(spacing: 0) {
                sidebar.frame(width: 230).clipped()   // keep group separators inside the column
                Divider().overlay(theme.border)
                content(selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.bg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // fills the right-side drawer
        #else
        NavigationStack {
            List {
                ForEach(Array(SettingsSection.groups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group.1) { s in
                            NavigationLink { content(s).navigationTitle(LocalizedStringKey(s.title)) } label: { row(s) }
                                .listRowBackground(theme.panel)
                                .listRowSeparatorTint(theme.border)
                        }
                    } header: {
                        if let label = group.0 {
                            Text(LocalizedStringKey(label))
                                .font(.ody(.caption, design: .monospaced))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .themedNavBar(theme)
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        #endif
    }

    private var header: some View {
        HStack {
            Image(systemName: "gearshape.fill").foregroundStyle(theme.accent)
            Text("Ajustes").font(.ody(.headline, design: .monospaced)).foregroundStyle(theme.fg)
            Spacer()
            Button("Concluído") { if let onClose { onClose() } else { dismiss() } }
                .font(.ody(.body, design: .monospaced)).foregroundStyle(theme.accent)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(theme.bg)
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(SettingsSection.groups.enumerated()), id: \.offset) { idx, group in
                    if let label = group.0 {
                        Text(LocalizedStringKey(label)).font(.ody(size: 10, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.horizontal, 12).padding(.top, 10)
                    } else if idx > 0 {
                        // Contained separator (a full-width Divider was bleeding past the
                        // sidebar column into the content pane).
                        Rectangle().fill(theme.border).frame(height: 1)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                    ForEach(group.1) { s in
                        Button { selection = s } label: { row(s, active: selection == s) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(theme.panel.opacity(0.4))
    }

    private func row(_ s: SettingsSection, active: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: s.icon).frame(width: 18).foregroundStyle(active ? theme.accent : theme.secondaryText)
            Text(LocalizedStringKey(s.title)).font(.ody(.subheadline, design: .monospaced))
                .foregroundStyle(active ? theme.fg : theme.fg.opacity(0.85))
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(active ? theme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func content(_ s: SettingsSection) -> some View {
        switch s {
        case .addModels: AddModelsSection(app: app)
        case .aiDefaults: AIDefaultsSection(app: app)
        case .addedModels: AddedModelsSection(app: app)
        case .search: SearchSection(app: app)
        case .appearance: ThemePickerView(inSheet: false).environmentObject(themes)
        case .language: LanguageSection()
        case .account: AccountSection()
        case .server: ServerSection()
        case .email: EmailSection(app: app)
        case .reminders: RemindersSection(app: app)
        case .imageGen: DiffusionServersView()
        case .integrations: IntegracoesSection(app: app)
        case .agentTools: AgentToolsSection(app: app)
        case .users: UsuariosSection(app: app)
        case .system: SistemaSection(app: app)
        }
    }
}

// MARK: - Reusable section chrome

struct SettingsScroll<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: () -> Content
    @Environment(\.theme) private var theme

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.subtitle = subtitle; self.content = content
   }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(title)).font(.ody(.title3, design: .monospaced).weight(.semibold)).foregroundStyle(theme.fg)
                    if let subtitle { Text(LocalizedStringKey(subtitle)).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText) }
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(theme.bg)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))
    }
}

/// Lightweight server picker shown from the login screen.
struct ServerSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://meu-servidor:porta", text: $text)
                        .font(.ody(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .listRowBackground(theme.panel)
                } header: {
                    Text("Endereço do servidor Odysseus")
                        .font(.ody(.caption, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .navigationTitle("Servidor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        if let url = ServerConfig.normalize(text) { app.updateServer(url) }
                        dismiss()
                    }
                    .disabled(ServerConfig.normalize(text) == nil)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .themedNavBar(theme)
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .onAppear { text = app.serverConfig.baseURL.absoluteString }
    }
}
