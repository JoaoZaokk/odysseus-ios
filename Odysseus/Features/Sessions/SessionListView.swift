import SwiftUI

/// The unified sidebar: what the user came for — the conversations — right
/// under one quick action and one collapsed group of feature sections.
///
/// The 1.8 layout stacked three quick actions and nine two-line "Espaços"
/// rows above the first conversation: on a 6.1" iPhone the list started a
/// whole screen below the top, and a German review called the result
/// "sehr unaufgeräumt". The web reference puts Chats right after New chat
/// and Search, with its tools last, single-line.
struct SidebarView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var workspace: WorkspaceStore
    @Binding var showSettings: Bool
    @Environment(\.theme) private var theme
    @EnvironmentObject private var themes: ThemeStore
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    @State private var search = ""
    @State private var renaming: ChatSession?
    @State private var renameText = ""
    /// nil = never touched: iPhone starts collapsed (the sections would push
    /// the conversations below the fold), iPad and macOS start open.
    @AppStorage("sidebar.spaces.expanded") private var spacesExpandedStored: Bool?

    private var filtered: [ChatSession] {
        guard !search.isEmpty else { return store.sessions }
        return store.sessions.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private func active(_ kind: WorkspacePane.Kind) -> Bool {
        workspace.panes.contains { $0.kind == kind }
    }

    private var spacesExpandedDefault: Bool {
        #if os(macOS)
        return true
        #else
        return sizeClass == .regular
        #endif
    }

    private var spacesExpanded: Binding<Bool> {
        Binding(get: { spacesExpandedStored ?? spacesExpandedDefault },
                set: { spacesExpandedStored = $0 })
    }

    var body: some View {
        List {
            // Navigation stays out of the way while a search is typed: the
            // matches are what the user is looking at, not Deep Search.
            if search.isEmpty {
                // "Nova conversa" lives in the chrome (the toolbar pencil) —
                // a second copy as the first row was the same action twice
                // on one screen. Theme lives in Settings › Aparência.
                Section {
                    navRow(icon: "sparkle.magnifyingglass", title: "Deep Search", tint: theme.green,
                           active: active(.deepSearch)) { workspace.openDeepSearch() }
                }

                // Feature sections: one line each, collapsible, header always
                // on screen so the nine entry points never scroll away.
                Section(isExpanded: spacesExpanded) {
                    ForEach(AppSection.allCases) { section in
                        Button { workspace.setPrimary(.section(section)) } label: { sectionRow(section) }
                            .buttonStyle(.plain)
                            .listRowBackground(active(.section(section)) ? theme.accent.opacity(0.14) : theme.bg)
                    }
                } header: {
                    header("Espaços")
                }
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
                // A failed load is not an empty account: saying "no conversations
                // yet" to someone whose sessions merely failed to fetch tells them
                // their history is gone. The error also needs a home when the list
                // is NOT empty — a rejected delete or rename used to look like the
                // app had simply ignored the tap.
                if let e = store.error {
                    Text(LocalizedStringKey(e))
                        .font(.ody(.footnote))
                        .foregroundStyle(theme.danger)
                        .listRowBackground(theme.bg)
                } else if store.sessions.isEmpty && !store.loading {
                    Text("Nenhuma conversa ainda.")
                        .font(.ody(.footnote))
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
            .font(.ody(.caption))
            .foregroundStyle(theme.secondaryText)
    }

    private func navRow(icon: String, title: String, tint: Color, active: Bool,
                        _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(LocalizedStringKey(title)).font(.ody(.subheadline)).foregroundStyle(theme.fg)
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
            Text(LocalizedStringKey(section.title))
                .font(.ody(.subheadline))
                .foregroundStyle(theme.fg)
                .lineLimit(1)
        } icon: {
            Image(systemName: section.icon).foregroundStyle(theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// One line: pin glyph and title. The model is already in the chat
    /// header, and a second line per row was what made the list read as
    /// twice as long as it is.
    private func chatRow(_ session: ChatSession) -> some View {
        HStack(spacing: 8) {
            if session.pinned {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(theme.accent)
            }
            Text(session.title)
                .font(.ody(.subheadline))
                .foregroundStyle(theme.fg).lineLimit(1)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
