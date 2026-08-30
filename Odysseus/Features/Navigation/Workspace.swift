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

        /// A pane addresses a *conversation*, not a snapshot of one. Synthesized
        /// equality compared every `ChatSession` field — including `title`,
        /// `pinned` and `updatedAt`, which changes on every message — so the two
        /// places that compare panes by kind (`openBeside`'s duplicate guard and
        /// the sidebar's open-marker) stopped recognising a chat as soon as the
        /// user touched it: clicking it again opened a second pane of the same
        /// conversation. Identity is the id; the rest is display state.
        static func == (a: Kind, b: Kind) -> Bool {
            switch (a, b) {
            case (.newChat, .newChat), (.deepSearch, .deepSearch): return true
            case let (.chat(x), .chat(y)): return x.id == y.id
            case let (.researchChat(x), .researchChat(y)): return x == y
            case let (.section(x), .section(y)): return x == y
            case let (.visualReport(x, _), .visualReport(y, _)): return x == y
            default: return false
            }
        }
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
