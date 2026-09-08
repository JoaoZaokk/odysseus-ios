import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var archived: [ChatSession] = []
    @Published var loading = false
    @Published var error: String?
    /// Message-content hits for the current search text.
    @Published var hits: [MessageSearchHit] = []
    @Published var hitsError: String?
    /// Sessions with a reply streaming right now (this app's own streams).
    @Published var streaming: Set<String> = []
    private var searchTask: Task<Void, Never>?

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

    // MARK: - Date buckets (sessions.js, calendar-day deltas)

    /// The label of the group a session falls in. Weekday and month labels
    /// come from the formatter, not the catalogue.
    static func bucket(_ ts: Double?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let ts, ts > 0 else { return "Mais antigas" }
        let date = Date(timeIntervalSince1970: ts)
        let start = calendar.startOfDay(for: date), today = calendar.startOfDay(for: now)
        let diff = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        if diff <= 0 { return "Hoje" }
        if diff == 1 { return "Ontem" }
        if diff < 7 {
            let f = DateFormatter(); f.locale = .current; f.setLocalizedDateFormatFromTemplate("EEEE")
            return f.string(from: date).capitalized
        }
        if diff >= 365 { let y = diff / 365; return y == 1 ? L("%d ano atrás", 1) : L("%d anos atrás", y) }
        if diff >= 180 { return "6 meses atrás" }
        if diff >= 30 { return L("%d dias atrás", (diff / 30) * 30) }
        let f = DateFormatter(); f.locale = .current
        f.setLocalizedDateFormatFromTemplate(calendar.component(.year, from: date) == calendar.component(.year, from: now) ? "d MMMM" : "d MMMM y")
        return f.string(from: date)
    }

    /// Pinned first under "Favoritos", then the rest in the list's order,
    /// split wherever the bucket label changes.
    static func groups(_ list: [ChatSession]) -> [(label: String, sessions: [ChatSession])] {
        var out: [(label: String, sessions: [ChatSession])] = []
        let pinned = list.filter(\.pinned)
        if !pinned.isEmpty { out.append((label: "Favoritos", sessions: pinned)) }
        for s in list where !s.pinned {
            let b = bucket(s.updatedAt)
            if let last = out.indices.last, out[last].label == b, out[last].label != "Favoritos" { out[last].sessions.append(s) }
            else { out.append((label: b, sessions: [s])) }
        }
        return out
    }

    // MARK: - Content search and activity

    func search(_ q: String) {
        searchTask?.cancel()
        let text = q.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { hits = []; hitsError = nil; return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else { return }
            do { hits = try await api.searchMessages(text); hitsError = nil }
            catch let e where e.isCancellation {
            } catch { hitsError = SettingsUI.failure(error, "Falha na busca: %@") }
        }
    }

    func markStreaming(_ id: String, _ on: Bool) {
        if on { streaming.insert(id) } else { streaming.remove(id) }
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
