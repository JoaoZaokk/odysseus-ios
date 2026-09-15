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
    @State private var deleting: ChatSession?
    @State private var showArchived = false
    /// The Espaços that do not fit in the bottom bar.
    @State private var showMoreSpaces = false
    /// Collapsed date groups, comma-joined (the web keeps the same set).
    @AppStorage("sidebar.dates.collapsed") private var collapsedRaw = ""
    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }
    private func toggleGroup(_ label: String) {
        var c = collapsed
        if c.contains(label) { c.remove(label) } else { c.insert(label) }
        collapsedRaw = c.sorted().joined(separator: ",")
    }
    /// nil = never touched: iPhone starts collapsed (the sections would push
    /// the conversations below the fold), iPad and macOS start open.
    @AppStorage("sidebar.spaces.expanded") private var spacesExpandedStored: Bool?
    /// Settings › Aparência › Personalizar interface: rows the user hid.
    @AppStorage(UIVisibility.storageKey) private var uiRaw = ""
    private var ui: UIVisibility { UIVisibility(raw: uiRaw) }
    private var visibleSections: [AppSection] { AppSection.allCases.filter { ui.shows($0) } }

    private var filtered: [ChatSession] {
        guard !search.isEmpty else { return store.sessions }
        return store.sessions.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private func active(_ kind: WorkspacePane.Kind) -> Bool {
        workspace.panes.contains { $0.kind == kind }
    }

    /// On a phone the Espaços go in a bar pinned to the bottom instead of rows
    /// in the list: nine of them above the first conversation is what a German
    /// review called "sehr unaufgeräumt", and collapsing them hid the app's
    /// nine entry points behind a chevron.
    private var usesSpacesBar: Bool {
        #if os(iOS)
        return sizeClass == .compact && !visibleSections.isEmpty
        #else
        return false
        #endif
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
            // The search field sits at the top, over what it filters: iOS 26
            // floats `.searchable` at the BOTTOM of the screen, far from the
            // list and a thumb's width from another screen's message field.
            Section {
                OdySearchField(text: $search, prompt: "Buscar conversas")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(theme.bg)
                    .listRowSeparator(.hidden)
            }

            // Navigation stays out of the way while a search is typed: the
            // matches are what the user is looking at, not Deep Search.
            if search.isEmpty {
                // "Nova conversa" lives in the chrome (the toolbar pencil) —
                // a second copy as the first row was the same action twice
                // on one screen. Theme lives in Settings › Aparência.
                if ui.isOn(.deepSearch) {
                    Section {
                        navRow(icon: "sparkle.magnifyingglass", title: "Deep Search", tint: theme.green,
                               active: active(.deepSearch)) { workspace.openDeepSearch() }
                    }
                }

                // Feature sections: one line each, collapsible, header always
                // on screen so the nine entry points never scroll away.
                // Rows hidden in Aparência are gone, and so is the group
                // once nothing is left in it.
                if !visibleSections.isEmpty && !usesSpacesBar {
                    Section(isExpanded: spacesExpanded) {
                        ForEach(visibleSections) { section in
                            Button { workspace.setPrimary(.section(section)) } label: { sectionRow(section) }
                                .buttonStyle(.plain)
                                .listRowBackground(active(.section(section)) ? theme.accent.opacity(0.14) : theme.bg)
                        }
                    } header: {
                        header("Espaços")
                    }
                }
            }

            // Message-content hits, from the server's FTS index.
            if !search.isEmpty {
                Section {
                    if let e = store.hitsError {
                        Text(LocalizedStringKey(e)).font(.ody(.footnote)).foregroundStyle(theme.danger).listRowBackground(theme.bg)
                    } else if store.hits.isEmpty {
                        Text("Nenhum resultado nas mensagens.").font(.ody(.footnote)).foregroundStyle(theme.secondaryText).listRowBackground(theme.bg)
                    }
                    ForEach(store.hits) { hit in
                        Button {
                            let s = store.sessions.first { $0.id == hit.sessionID } ?? ChatSession(id: hit.sessionID, title: hit.sessionName)
                            workspace.setPrimary(.chat(s))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.sessionName).font(.ody(.subheadline)).foregroundStyle(theme.fg).lineLimit(1)
                                Text((hit.role == "user" ? L("Você") : L("IA")) + ": " + hit.snippet)
                                    .font(.ody(.caption)).foregroundStyle(theme.secondaryText).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(theme.bg)
                    }
                } header: { header("Nas mensagens") }
            }

            // Conversations, in date groups; each group folds.
            ForEach(SessionStore.groups(filtered), id: \.label) { group in
              Section {
                if !collapsed.contains(group.label) {
                ForEach(group.sessions) { session in
                    Button { workspace.setPrimary(.chat(session)) } label: { chatRow(session) }
                        .buttonStyle(.plain)
                        .listRowBackground(rowBackground(active: active(.chat(session))))
                        // The sidebar style draws a hairline between some rows
                        // and not others; asking for it on every row is what
                        // makes the list read as a list.
                        .listRowSeparator(.visible)
                        .listRowSeparatorTint(theme.border)
                        // Delete is final on the server, so it asks; archive
                        // is the reversible way to get a row off the list.
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleting = session } label: { Label("Apagar", systemImage: "trash") }
                            Button { Task { await store.archive(session) } } label: { Label("Arquivar", systemImage: "archivebox") }
                                .tint(theme.warning)
                            Button {
                                renaming = session; renameText = session.title
                            } label: { Label("Renomear", systemImage: "pencil") }
                            .tint(theme.border)
                        }
                        .swipeActions(edge: .leading) {
                            Button { Task { await store.setPinned(session, !session.pinned) } } label: {
                                Label(session.pinned ? "Desafixar" : "Fixar", systemImage: session.pinned ? "pin.slash" : "pin")
                            }
                            .tint(theme.accent)
                        }
                        .contextMenu {
                            Button { Task { await store.setPinned(session, !session.pinned) } } label: {
                                Label(session.pinned ? "Desafixar" : "Fixar", systemImage: session.pinned ? "pin.slash" : "pin")
                            }
                            Button { Task { await store.archive(session) } } label: { Label("Arquivar", systemImage: "archivebox") }
                            Button { renaming = session; renameText = session.title } label: { Label("Renomear", systemImage: "pencil") }
                            Button(role: .destructive) { deleting = session } label: { Label("Apagar", systemImage: "trash") }
                        }
                }
                }
              } header: {
                // A band the width of the list, with the number of conversations
                // in it: the old header was a caption floating in the same tone
                // as the rows, so a group started without anything marking it.
                Button { toggleGroup(group.label) } label: {
                    HStack(spacing: 6) {
                        Text(LocalizedStringKey(group.label))
                            .font(.ody(size: 10, weight: .semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(theme.secondaryText)
                        Image(systemName: collapsed.contains(group.label) ? "chevron.right" : "chevron.down")
                            .font(.ody(size: 8)).foregroundStyle(theme.secondaryText)
                        Spacer()
                        Text("\(group.sessions.count)")
                            .font(.ody(size: 10))
                            .foregroundStyle(theme.secondaryText.opacity(0.7))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.panel)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
              }
            }
            Section {
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
                HStack {
                    header("Conversas")
                    Spacer()
                    // The archive lives behind the header, not as a tenth
                    // Espaço row above the list.
                    Button { showArchived = true } label: {
                        Label("Arquivadas", systemImage: "archivebox")
                            .font(.ody(.caption))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        // Opaque base bg (not the translucent `theme.bg`) so the system sidebar
        // vibrancy never bleeds through when "transparência" is on — keeps the
        // sidebar tone consistent with the rest of the UI.
        .background(themes.theme.bg)
        #if os(iOS)
        .safeAreaInset(edge: .bottom) {
            if usesSpacesBar && search.isEmpty { spacesBar }
        }
        .sheet(isPresented: $showMoreSpaces) { moreSpacesSheet }
        #endif
        .onChange(of: search) { _, q in store.search(q) }
        .screenChrome(title: "Odysseus") {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
        } trailing: {
            Button { workspace.setPrimary(.newChat) } label: { Image(systemName: "square.and.pencil") }
        }
        .odyRefreshable { await store.load() }
        .sheet(isPresented: $showArchived) {
            ArchivedSessionsView(store: store, workspace: workspace)
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
        .alert(deleting?.title ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Apagar", role: .destructive) { if let s = deleting { Task { await store.delete(s) } }; deleting = nil }
            Button("Cancelar", role: .cancel) { deleting = nil }
        } message: { Text("Isso é irreversível. Confirma?") }
    }

    #if os(iOS)
    /// Four Espaços and a way to the rest. Four because a fifth slot on a 6.1"
    /// phone leaves each label under 60 pt and the words are whole ones
    /// ("Cookbook", "Calendário"), not glyphs.
    private var barSections: [AppSection] {
        visibleSections.count <= 5 ? visibleSections : Array(visibleSections.prefix(4))
    }

    private var spacesBar: some View {
        HStack(spacing: 0) {
            ForEach(barSections) { section in
                barItem(icon: section.icon, title: section.title, active: active(.section(section))) {
                    workspace.setPrimary(.section(section))
                }
            }
            if barSections.count < visibleSections.count {
                barItem(icon: "ellipsis", title: "Mais", active: false) { showMoreSpaces = true }
            }
        }
        .padding(.top, 6)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                theme.panel
                Rectangle().fill(theme.border).frame(height: 1)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func barItem(icon: String, title: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.ody(size: 15))
                    .foregroundStyle(active ? theme.accent : theme.secondaryText)
                Text(LocalizedStringKey(title))
                    .font(.ody(size: 9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(active ? theme.fg : theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var moreSpacesSheet: some View {
        NavigationStack {
            List {
                ForEach(visibleSections.filter { s in !barSections.contains(where: { $0.id == s.id }) }) { section in
                    Button {
                        workspace.setPrimary(.section(section))
                        showMoreSpaces = false
                    } label: { sectionRow(section) }
                    .buttonStyle(.plain)
                    .listRowBackground(theme.bg)
                }
            }
            .listStyle(.plain)
            .background(theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("Espaços")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { showMoreSpaces = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
    #endif

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
    /// Two lines: the title with the time it was last touched, and the model
    /// that answered in it. The server's session list carries no message
    /// preview — `GET /api/sessions` returns id, title, model, timestamps and
    /// the two flags — so the second line says what there is, not a fake
    /// snippet.
    private func chatRow(_ session: ChatSession) -> some View {
        HStack(spacing: 8) {
            if session.pinned {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // The title takes the row's width itself instead of being
                    // sized to its text and clipped by the list: a long title
                    // was cut mid-word, with no ellipsis to say it had been.
                    Text(session.title)
                        .font(.ody(.subheadline))
                        .foregroundStyle(theme.fg)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let time = SessionStore.rowTime(session.updatedAt) {
                        Text(time)
                            .font(.ody(size: 10))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                if let model = session.model, !model.isEmpty {
                    Text(model)
                        .font(.ody(size: 11))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            if store.streaming.contains(session.id) {
                ProgressView().controlSize(.mini).tint(theme.accent)
                    .accessibilityLabel(Text("Gerando resposta…"))
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The row's background, with the accent bar that marks the open chat —
    /// a tint alone was easy to miss on the darker themes.
    private func rowBackground(active: Bool) -> some View {
        ZStack(alignment: .leading) {
            (active ? theme.accent.opacity(0.14) : theme.bg)
            if active { Rectangle().fill(theme.accent).frame(width: 3) }
        }
    }
}

/// The archived conversations: open one, or put it back on the list.
struct ArchivedSessionsView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var workspace: WorkspaceStore
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.archived) { session in
                    Button {
                        workspace.setPrimary(.chat(session))
                        dismiss()
                    } label: {
                        Text(session.title).font(.ody(.subheadline)).foregroundStyle(theme.fg).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(theme.panel)
                    .swipeActions(edge: .trailing) {
                        Button { Task { await store.unarchive(session) } } label: {
                            Label("Desarquivar", systemImage: "tray.and.arrow.up")
                        }
                        .tint(theme.accent)
                    }
                    .contextMenu {
                        Button { Task { await store.unarchive(session) } } label: {
                            Label("Desarquivar", systemImage: "tray.and.arrow.up")
                        }
                    }
                }
                if let e = store.error {
                    Text(LocalizedStringKey(e)).font(.ody(.footnote)).foregroundStyle(theme.danger)
                        .listRowBackground(theme.bg)
                } else if store.archived.isEmpty {
                    Text("Nenhuma conversa arquivada.").font(.ody(.footnote)).foregroundStyle(theme.secondaryText)
                        .listRowBackground(theme.bg)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Arquivadas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .themedNavBar(theme)
        }
        .tint(theme.accent)
        .task { await store.loadArchived() }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }
}
