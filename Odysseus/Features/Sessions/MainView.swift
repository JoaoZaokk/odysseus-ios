import SwiftUI

struct MainView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var themes: ThemeStore
    @Environment(\.theme) private var theme
    @StateObject private var store: SessionStore
    @StateObject private var workspace = WorkspaceStore()
    @State private var showSettings = false
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @State private var compactColumn = NavigationSplitViewColumn.sidebar

    init(app: AppState) {
        _store = StateObject(wrappedValue: app.makeSessionStore())
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            SidebarView(store: store, workspace: workspace, showSettings: $showSettings)
                .navigationSplitViewColumnWidth(min: 270, ideal: 310)
        } detail: {
            WorkspaceView(workspace: workspace, app: app, onNewSession: { Task { await store.load() } })
        }
        .navigationSplitViewStyle(.balanced)
        .tint(theme.accent)
        .task { await store.load() }
        // On iPhone (compact) the split view shows ONE column at a time. A sidebar
        // tap changes the workspace, so move the visible compact column to the
        // detail — otherwise the buttons look dead. `preferredCompactColumn` (not
        // `columnVisibility`) is what drives this on compact; iPad keeps both.
        .onChange(of: workspace.panes) { _, _ in
            compactColumn = .detail
        }
        #if os(macOS)
        // macOS: open Ajustes as a right-anchored panel (like the workspace panes),
        // not a floating centered sheet that bleeds off a large display.
        .overlay {
            if showSettings {
                ZStack(alignment: .trailing) {
                    // Backdrop covers the whole window (incl. behind the title bar);
                    // the panel itself stays inside the content area so its header
                    // (Ajustes / Concluído) clears the macOS title bar.
                    Color.black.opacity(0.18).ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                        .transition(.opacity)
                    SettingsView(onClose: close)
                        .environmentObject(app).environmentObject(themes)
                        .frame(width: 780)
                        .frame(maxHeight: .infinity)
                        .background(theme.bg)
                        .overlay(alignment: .leading) { Divider().overlay(theme.border) }
                        .shadow(color: .black.opacity(0.28), radius: 18, x: -6, y: 0)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .animation(.easeOut(duration: 0.22), value: showSettings)
        #else
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(app).environmentObject(themes)
        }
        #endif
    }

    private func close() { showSettings = false }
}

/// Placeholder for sections not yet wired up — keeps the hub honest and complete.
struct ComingSoonView: View {
    let section: AppSection
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: section.icon)
                    .font(.ody(size: 44))
                    .foregroundStyle(theme.accent)
                Text(LocalizedStringKey(section.title))
                    .font(.ody(.title2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(theme.fg)
                Text("Em construção — chega na próxima onda. 🛠️")
                    .font(.ody(.footnote, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .navigationTitle(LocalizedStringKey(section.title))
        .navigationBarTitleDisplayMode(.inline)
    }
}
