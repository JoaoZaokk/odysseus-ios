import SwiftUI

/// App-level commands the macOS menu bar exposes. Screens subscribe by name so
/// the menu does not need a reference into the view tree.
extension Notification.Name {
    /// File › Nova conversa (⌘N). Replaces WindowGroup's automatic "New Window",
    /// which owned ⌘N and silently beat the in-view shortcut.
    static let odysseusNewChat = Notification.Name("odysseus.newChat")
    /// View › Atualizar (⌘R). `.refreshable` has no gesture on macOS; every
    /// screen that pulls to refresh on iOS answers this instead.
    static let odysseusRefresh = Notification.Name("odysseus.refresh")
}

extension View {
    /// `.refreshable` on iOS; on macOS the same action answers ⌘R / View › Atualizar.
    @ViewBuilder
    func odyRefreshable(_ action: @escaping @Sendable () async -> Void) -> some View {
        #if os(macOS)
        self
            .refreshable { await action() }
            .onReceive(NotificationCenter.default.publisher(for: .odysseusRefresh)) { _ in Task { await action() } }
        #else
        self.refreshable { await action() }
        #endif
    }
}
