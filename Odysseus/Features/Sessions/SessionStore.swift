import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var archived: [ChatSession] = []
    @Published var loading = false
    @Published var error: String?

    private let api: APIClient
    /// Told the live count after every load — the review gate reads it.
    private let onCount: ((Int) -> Void)?
    init(api: APIClient, onCount: ((Int) -> Void)? = nil) { self.api = api; self.onCount = onCount }

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
            onCount?(sessions.count)
        } catch let e where e.isCancellation {
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadArchived() async {
        do { archived = try await api.archivedSessions(); error = nil }
        catch let e where e.isCancellation {
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    /// Archive keeps the data and takes the row off the list — the reversible
    /// alternative to a delete that, server-side, is final.
    func archive(_ session: ChatSession) async {
        do {
            try await api.archiveSession(session.id)
            sessions.removeAll { $0.id == session.id }
            onCount?(sessions.count)
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func unarchive(_ session: ChatSession) async {
        do {
            try await api.unarchiveSession(session.id)
            archived.removeAll { $0.id == session.id }
            await load()
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    /// The pin. On the server `is_important` is also the only thing that
    /// exempts a chat from automatic archiving and deletion.
    func setPinned(_ session: ChatSession, _ pinned: Bool) async {
        do {
            try await api.setImportant(session.id, pinned)
            if let i = sessions.firstIndex(where: { $0.id == session.id }) { sessions[i].pinned = pinned }
            sessions.sort { lhs, rhs in
                if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
                return (lhs.updatedAt ?? 0) > (rhs.updatedAt ?? 0)
            }
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func delete(_ session: ChatSession) async {
        do {
            try await api.deleteSession(session.id)
            sessions.removeAll { $0.id == session.id }
            onCount?(sessions.count)
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
