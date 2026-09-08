import Foundation
import UserNotifications
#if os(iOS)
import BackgroundTasks
#endif

/// The "browser" reminder channel, for the app: the server keeps an
/// in-memory queue the web tab polls at `/api/tasks/notifications`; the
/// read drains it. The app polls the same queue and posts each entry as a
/// local notification: every 30 s while it runs (on macOS that is as long
/// as it is open; on iOS, on screen), and on iOS also whenever the system
/// grants a background refresh. The server has no push — this is the
/// closest a client can get on its own, and a drained queue cannot be
/// re-read, so the two paths share one read.
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
    /// Injected for the same reason: the real one may show a system dialog.
    var authorize: () async -> Bool = { await TaskNotificationPoller.authorized() }

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
            guard await authorize() else { return }
            try? await Task.sleep(nanoseconds: UInt64(firstDelay * 1_000_000_000))
            while !Task.isCancelled {
                await refreshOnce()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    /// One read of the queue; every entry with a body becomes a notification.
    /// Shared by the foreground loop and the background refresh. Returns how
    /// many were posted.
    @discardableResult
    func refreshOnce() async -> Int {
        guard Self.isEnabled, let items = try? await poll(api) else { return 0 }
        var posted = 0
        for n in items where !(n.body ?? "").isEmpty { deliver(n); posted += 1 }
        return posted
    }

    /// The background entry: the system woke the app for a moment. No
    /// dialog can be shown here, so an undecided permission means no read.
    func backgroundRefresh() async {
        guard Self.isEnabled, await authorize() else { return }
        await refreshOnce()
    }

    #if os(iOS)
    /// Listed in `BGTaskSchedulerPermittedIdentifiers` (project.yml).
    static let refreshTaskID = "com.zao.odysseus.tasks.refresh"

    /// Asked for on every trip to the background and after every refresh;
    /// the system decides when — never sooner than this, and only for apps
    /// the person actually opens. A no-op on the simulator (submit throws).
    static func scheduleBackgroundRefresh() {
        guard isEnabled else { return }
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }
    #endif

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
