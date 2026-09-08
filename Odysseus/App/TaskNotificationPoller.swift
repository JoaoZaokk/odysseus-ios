import Foundation
import UserNotifications

/// The "browser" reminder channel, for the app: the server keeps an
/// in-memory queue the web tab polls at `/api/tasks/notifications`; the
/// read drains it. While the app is in the foreground it polls the same
/// queue and posts each entry as a local notification. Foreground only —
/// the server has no push, and a drained queue cannot be re-read.
@MainActor final class TaskNotificationPoller {
    /// Opt-in from Conta. Off by default so no permission prompt appears
    /// unasked on a first launch.
    static let enabledKey = "notifications.tasks"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    private var task: Task<Void, Never>?
    private let api: APIClient
    private let poll: (APIClient) async throws -> [TaskNotification]
    /// Injected so the wire can be tested without UNUserNotificationCenter.
    var deliver: (TaskNotification) -> Void

    init(api: APIClient, poll: @escaping (APIClient) async throws -> [TaskNotification] = { try await $0.taskNotifications() }) {
        self.api = api
        self.poll = poll
        self.deliver = Self.post
    }

    var isRunning: Bool { task != nil }

    func start(firstDelay: Double = 1.5, interval: Double = 30) {
        guard task == nil, Self.isEnabled else { return }
        task = Task { [weak self] in
            guard let self else { return }
            guard await Self.authorized() else { return }
            try? await Task.sleep(nanoseconds: UInt64(firstDelay * 1_000_000_000))
            while !Task.isCancelled {
                if let items = try? await poll(api) {
                    for n in items where !(n.body ?? "").isEmpty { deliver(n) }
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    /// Asked at most once; a denial ends the poller for good this launch.
    static func authorized() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default: return false
        }
    }

    private static func post(_ n: TaskNotification) {
        let content = UNMutableNotificationContent()
        content.title = n.taskName ?? L("Tarefa")
        content.body = n.body ?? ""
        content.sound = .default
        let id = "task-\(n.taskID ?? UUID().uuidString)-\(n.timestamp ?? "")"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

/// One entry of `GET /api/tasks/notifications` (`{"notifications": [...]}`).
struct TaskNotification: Decodable, Sendable {
    let taskName: String?
    let status: String?
    let taskID: String?
    let body: String?
    let timestamp: String?
    enum CodingKeys: String, CodingKey { case taskName = "task_name", status, taskID = "task_id", body, timestamp }
}

extension APIClient {
    func taskNotifications() async throws -> [TaskNotification] {
        decodeList(TaskNotification.self, try await send(request("/api/tasks/notifications")))
    }
}
