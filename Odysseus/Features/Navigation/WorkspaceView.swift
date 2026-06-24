import SwiftUI

/// The detail area: side-by-side resizable columns on macOS (native `HSplitView`),
/// a single pane on iOS. Each column's header gets ↗/× via `\.paneControls`.
struct WorkspaceView: View {
    @ObservedObject var workspace: WorkspaceStore
    let app: AppState
    var onNewSession: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            #if os(macOS)
            HSplitView {
                ForEach(workspace.panes) { pane in
                    paneContent(pane)
                        .environment(\.paneControls, controls(for: pane))
                        .frame(minWidth: 320)
                }
            }
            #else
            paneContent(workspace.panes.last ?? WorkspacePane(kind: .newChat))
            #endif
        }
        .background(theme.bg)
    }

    private func controls(for pane: WorkspacePane) -> PaneControls {
        guard workspace.panes.count > 1 else { return PaneControls() }
        return PaneControls(
            onExpand: { workspace.expand(pane) },
            onClose: { workspace.close(pane) }
        )
    }

    @ViewBuilder
    private func paneContent(_ pane: WorkspacePane) -> some View {
        switch pane.kind {
        case .newChat:
            ChatScreen(app: app, session: nil, deepSearch: false) { _ in onNewSession() }
                .id(pane.id)
        case .chat(let s):
            ChatScreen(app: app, session: s, deepSearch: false) { _ in onNewSession() }
                .id(s.id)
        case .researchChat(let prompt):
            ChatScreen(app: app, session: nil, deepSearch: true, autoSend: prompt) { _ in onNewSession() }
                .id(pane.id)
        case .deepSearch:
            DeepResearchView(app: app, workspace: workspace)
        case .section(let s):
            sectionView(s)
        case .visualReport(let id, let title):
            VisualReportView(app: app, reportID: id, title: title)
        }
    }

    @ViewBuilder
    private func sectionView(_ s: AppSection) -> some View {
        switch s {
        case .brain: BrainView(app: app)
        case .notes: NotesView(app: app)
        case .calendar: CalendarView(app: app)
        case .gallery: GalleryView(app: app)
        case .email: EmailView(app: app)
        case .tasks: TasksView(app: app)
        case .library: LibraryView(app: app)
        case .compare: CompareView(app: app)
        case .cookbook: CookbookView(app: app)
        }
    }
}
