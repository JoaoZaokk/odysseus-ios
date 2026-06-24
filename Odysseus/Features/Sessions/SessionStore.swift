import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var loading = false
    @Published var error: String?

    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let all = try await api.sessions()
            // Hide archived; pinned first, then most-recent.
            sessions = all
                .filter { !$0.archived }
                .sorted { lhs, rhs in
                    if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
                    return (lhs.updatedAt ?? 0) > (rhs.updatedAt ?? 0)
                }
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func delete(_ session: ChatSession) async {
        do {
            try await api.deleteSession(session.id)
            sessions.removeAll { $0.id == session.id }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func rename(_ session: ChatSession, to name: String) async {
        do {
            try await api.renameSession(session.id, to: name)
            if let i = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[i].title = name
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
