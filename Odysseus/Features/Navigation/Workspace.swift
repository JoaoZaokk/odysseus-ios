import SwiftUI

/// One open pane in the workspace (a column in the macOS split view).
struct WorkspacePane: Identifiable, Equatable {
    let id = UUID()
    var kind: Kind

    enum Kind: Equatable {
        case newChat
        case chat(ChatSession)
        case researchChat(prompt: String)
        case deepSearch
        case section(AppSection)
        case visualReport(id: String, title: String)
    }

    var isChatLike: Bool {
        switch kind { case .newChat, .chat: return true; default: return false }
    }
}

/// The set of side-by-side panes. Sidebar actions set the *primary* pane; Deep
/// Research / Visual Report open *beside* it (native split columns on macOS).
@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var panes: [WorkspacePane] = [WorkspacePane(kind: .newChat)]
    let maxPanes = 3

    private var hasChat: Bool { panes.contains { $0.isChatLike } }

    /// Replace the whole workspace with a single pane (normal navigation).
    func setPrimary(_ kind: WorkspacePane.Kind) {
        panes = [WorkspacePane(kind: kind)]
    }

    /// Add a pane to the right (capped at `maxPanes`).
    func openBeside(_ kind: WorkspacePane.Kind) {
        if panes.contains(where: { $0.kind == kind }) { return }
        if panes.count >= maxPanes { panes.removeLast() }
        panes.append(WorkspacePane(kind: kind))
    }

    /// Deep Research splits beside a chat; on its own otherwise.
    func openDeepSearch() {
        if panes.contains(where: { $0.kind == .deepSearch }) { return }
        if hasChat { openBeside(.deepSearch) } else { setPrimary(.deepSearch) }
    }

    func openVisualReport(id: String, title: String) {
        openBeside(.visualReport(id: id, title: title))
    }

    func close(_ pane: WorkspacePane) {
        panes.removeAll { $0.id == pane.id }
        if panes.isEmpty { panes = [WorkspacePane(kind: .newChat)] }
    }

    /// Make this pane the only one (the "expand" / throw-to-corner action).
    func expand(_ pane: WorkspacePane) {
        panes = [pane]
    }
}

// MARK: - Pane controls (injected so each screen's header gets ↗ / × on macOS)

struct PaneControls {
    var onExpand: (() -> Void)?
    var onClose: (() -> Void)?
}

private struct PaneControlsKey: EnvironmentKey {
    static let defaultValue = PaneControls()
}

extension EnvironmentValues {
    var paneControls: PaneControls {
        get { self[PaneControlsKey.self] }
        set { self[PaneControlsKey.self] = newValue }
    }
}
