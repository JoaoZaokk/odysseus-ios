import SwiftUI

/// The unified sidebar: feature sections at the top, conversation list below.
struct SidebarView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var workspace: WorkspaceStore
    @Binding var showSettings: Bool
    @Environment(\.theme) private var theme
    @EnvironmentObject private var themes: ThemeStore

    @State private var search = ""
    @State private var renaming: ChatSession?
    @State private var renameText = ""
    @State private var showThemes = false

    private var filtered: [ChatSession] {
        guard !search.isEmpty else { return store.sessions }
        return store.sessions.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private func active(_ kind: WorkspacePane.Kind) -> Bool {
        workspace.panes.contains { $0.kind == kind }
    }

    var body: some View {
        List {
            // Quick actions
            Section {
                navRow(icon: "square.and.pencil", title: "Nova conversa", tint: theme.accent,
                       active: active(.newChat)) { workspace.setPrimary(.newChat) }
                navRow(icon: "sparkle.magnifyingglass", title: "Deep Search", tint: theme.green,
                       active: active(.deepSearch)) { workspace.openDeepSearch() }
                Button { showThemes = true } label: {
                    Label {
                        Text("Tema").font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                    } icon: {
                        Image(systemName: "paintpalette").foregroundStyle(theme.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(theme.bg)
            }

            // Feature sections
            Section {
                ForEach(AppSection.allCases) { section in
                    Button { workspace.setPrimary(.section(section)) } label: { sectionRow(section) }
                        .buttonStyle(.plain)
                        .listRowBackground(active(.section(section)) ? theme.accent.opacity(0.14) : theme.bg)
                }
            } header: {
                header("Espaços")
            }

            // Conversations
            Section {
                ForEach(filtered) { session in
                    Button { workspace.setPrimary(.chat(session)) } label: { chatRow(session) }
                        .buttonStyle(.plain)
                        .listRowBackground(active(.chat(session)) ? theme.accent.opacity(0.14) : theme.bg)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await store.delete(session) }
                            } label: { Label("Apagar", systemImage: "trash") }
                            Button {
                                renaming = session; renameText = session.title
                            } label: { Label("Renomear", systemImage: "pencil") }
                            .tint(theme.border)
                        }
                }
                if store.sessions.isEmpty && !store.loading {
                    Text("Nenhuma conversa ainda.")
                        .font(.ody(.footnote, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                        .listRowBackground(theme.bg)
                }
            } header: {
                header("Conversas")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        // Opaque base bg (not the translucent `theme.bg`) so the system sidebar
        // vibrancy never bleeds through when "transparência" is on — keeps the
        // sidebar tone consistent with the rest of the UI.
        .background(themes.theme.bg)
        .odySearchable(text: $search, prompt: "Buscar conversas")
        .screenChrome(title: "Odysseus") {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
        } trailing: {
            Button { workspace.setPrimary(.newChat) } label: { Image(systemName: "square.and.pencil") }
        }
        .refreshable { await store.load() }
        .sheet(isPresented: $showThemes) {
            ThemePickerView(inSheet: true)
                .environmentObject(themes)
        }
        .alert("Renomear conversa", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nome", text: $renameText)
            Button("Salvar") {
                if let s = renaming { Task { await store.rename(s, to: renameText) } }
                renaming = nil
            }
            Button("Cancelar", role: .cancel) { renaming = nil }
        }
    }

    private func header(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(.ody(.caption, design: .monospaced))
            .foregroundStyle(theme.secondaryText)
    }

    private func navRow(icon: String, title: String, tint: Color, active: Bool,
                        _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(LocalizedStringKey(title)).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
            } icon: {
                Image(systemName: icon).foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(active ? theme.accent.opacity(0.14) : theme.bg)
    }

    private func sectionRow(_ section: AppSection) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(section.title))
                        .font(.ody(.subheadline, design: .monospaced))
                        .foregroundStyle(theme.fg)
                    if !section.implemented {
                        Text("em breve")
                            .font(.ody(size: 9, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(theme.panel, in: Capsule())
                    }
                }
                Text(LocalizedStringKey(section.subtitle))
                    .font(.ody(size: 10, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: section.icon).foregroundStyle(theme.accent)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func chatRow(_ session: ChatSession) -> some View {
        HStack(spacing: 8) {
            if session.pinned {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.ody(.subheadline, design: .monospaced))
                    .foregroundStyle(theme.fg).lineLimit(1)
                if let m = session.shortModel {
                    Text(m).font(.ody(size: 10, design: .monospaced))
                        .foregroundStyle(theme.secondaryText).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
