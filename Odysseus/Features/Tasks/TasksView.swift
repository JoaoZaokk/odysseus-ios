import SwiftUI

// MARK: - Model

struct ScheduledTask: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var taskType: String
    var action: String?
    var schedule: String?
    var scheduledTime: String?
    var cronExpression: String?
    var triggerType: String?
    var triggerEvent: String?
    var nextRun: String?
    var lastRun: String?
    var status: String
    var runCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, action, schedule, status
        case taskType = "task_type"
        case scheduledTime = "scheduled_time"
        case cronExpression = "cron_expression"
        case triggerType = "trigger_type"
        case triggerEvent = "trigger_event"
        case nextRun = "next_run"
        case lastRun = "last_run"
        case runCount = "run_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A numeric id decodes too — the sibling models (Note, GalleryImage,
        // EmailAccount, ChatSession) all carry this branch. Without it the row
        // gets a client-invented UUID, and every button on it addresses nothing.
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) }
        else { id = UUID().uuidString }
        name = (try? c.decode(String.self, forKey: .name)) ?? "(sem nome)"
        taskType = (try? c.decode(String.self, forKey: .taskType)) ?? "prompt"
        action = try? c.decodeIfPresent(String.self, forKey: .action)
        schedule = try? c.decodeIfPresent(String.self, forKey: .schedule)
        scheduledTime = try? c.decodeIfPresent(String.self, forKey: .scheduledTime)
        cronExpression = try? c.decodeIfPresent(String.self, forKey: .cronExpression)
        triggerType = try? c.decodeIfPresent(String.self, forKey: .triggerType)
        triggerEvent = try? c.decodeIfPresent(String.self, forKey: .triggerEvent)
        nextRun = try? c.decodeIfPresent(String.self, forKey: .nextRun)
        lastRun = try? c.decodeIfPresent(String.self, forKey: .lastRun)
        status = (try? c.decode(String.self, forKey: .status)) ?? "active"
        runCount = (try? c.decode(Int.self, forKey: .runCount)) ?? 0
    }

    var isPaused: Bool { status == "paused" }

    /// Human description of when this task fires.
    ///
    /// Resolved here rather than at the render site: every branch but one is
    /// interpolated, and an interpolated string can never match a catalogue key.
    var scheduleText: String {
        if (triggerType ?? "schedule") == "event" {
            return L("Evento: %@", triggerEvent ?? "?")
        }
        switch schedule {
        case "cron": return L("Cron: %@", cronExpression ?? "?")
        case "once": return L("Uma vez %@", scheduledTime ?? "")
        case "daily": return L("Diário %@", scheduledTime ?? "")
        case "hourly": return L("De hora em hora")
        case "weekly": return L("Semanal %@", scheduledTime ?? "")
        default: return scheduledTime.map { L("Agendado %@", $0) } ?? L("Manual")
        }
    }
}

// MARK: - API

extension APIClient {
    func tasks() async throws -> [ScheduledTask] {
        decodeList(ScheduledTask.self, try await send(request("/api/tasks")))
    }
    func runTask(_ id: String) async throws { _ = try await send(request("/api/tasks/\(encPath(id))/run?force=true", method: "POST")) }
    func pauseTask(_ id: String) async throws { _ = try await send(request("/api/tasks/\(encPath(id))/pause", method: "POST")) }
    func resumeTask(_ id: String) async throws { _ = try await send(request("/api/tasks/\(encPath(id))/resume", method: "POST")) }
}

// MARK: - View

@MainActor
final class TasksViewModel: ObservableObject {
    @Published var tasks: [ScheduledTask] = []
    @Published var loading = false
    @Published var busyID: String?
    @Published var error: String?

    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func load() async {
        loading = true; defer { loading = false }
        do { tasks = try await api.tasks(); error = nil }
        catch let e where e.isCancellation {}
        catch { self.error = SettingsUI.msg(error) }
    }
    func run(_ t: ScheduledTask) async {
        busyID = t.id; defer { busyID = nil }
        do { try await api.runTask(t.id) } catch { self.error = SettingsUI.msg(error) }
    }
    func toggle(_ t: ScheduledTask) async {
        busyID = t.id; defer { busyID = nil }
        do {
            if t.isPaused { try await api.resumeTask(t.id) } else { try await api.pauseTask(t.id) }
            await load()
        } catch { self.error = SettingsUI.msg(error) }
    }
}

struct TasksView: View {
    @StateObject private var vm: TasksViewModel
    @Environment(\.theme) private var theme
    init(app: AppState) { _vm = StateObject(wrappedValue: TasksViewModel(api: app.api)) }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            content
        }
        .screenChrome(title: "Tasks")
        .task { await vm.load() }
        .odyRefreshable { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.tasks.isEmpty && vm.loading {
            ProgressView().tint(theme.accent)
        } else if vm.tasks.isEmpty, let e = vm.error {
            LoadFailedView(message: e) { Task { await vm.load() } }
        } else if vm.tasks.isEmpty {
            EmptyStateView(icon: "checklist", title: "Sem tarefas",
                           message: "Agentes agendados do Odysseus aparecem aqui.")
        } else {
            List {
                ForEach(vm.tasks) { t in
                    taskRow(t)
                        .listRowBackground(theme.bg)
                        .gutterRowInsets(vertical: 10)
                        .rowSeparatorInset(Spacing.separatorInsetPlain)
                        .edgeSeparators(first: t.id == vm.tasks.first?.id, last: t.id == vm.tasks.last?.id)
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .listBottomBreathing()
            .readableColumn()
        }
    }

    /// Title with its state as a labelled pill (a bare dot said "active" in
    /// colour only), then schedule and runs on one line, then the actions.
    private func taskRow(_ t: ScheduledTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(t.name).font(.ody(.headline, weight: .semibold)).foregroundStyle(theme.fg)
                Spacer(minLength: 8)
                if vm.busyID == t.id { ProgressView().controlSize(.small) }
                stateBadge(paused: t.isPaused)
            }
            HStack(spacing: 12) {
                Text(verbatim: t.scheduleText)
                if let last = t.lastRun { meta(relative(last), icon: "clock.arrow.circlepath") }
                meta("\(t.runCount)×", icon: "repeat")
            }
            .font(.ody(.subheadline)).foregroundStyle(theme.secondaryText)
            .lineLimit(1).minimumScaleFactor(0.85)

            HStack(spacing: 10) {
                actionButton(t.isPaused ? "Retomar" : "Pausar", system: t.isPaused ? "play.fill" : "pause.fill") {
                    Task { await vm.toggle(t) }
                }
                actionButton("Rodar agora", system: "bolt.fill") { Task { await vm.run(t) } }
            }
            .padding(.top, 8)
        }
    }

    private func stateBadge(paused: Bool) -> some View {
        HStack(spacing: 5) {
            Circle().frame(width: 6, height: 6).accessibilityHidden(true)
            Text(LocalizedStringKey(paused ? "Pausada" : "Ativa"))
        }
        .font(.ody(.footnote, weight: .semibold))
        .foregroundStyle(paused ? theme.secondaryText : theme.green)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background((paused ? theme.fg : theme.green).opacity(paused ? 0.08 : 0.14), in: Capsule())
    }

    /// Icon tight against its value: a `Label` left a word's width between them.
    private func meta(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(verbatim: text)
        }
    }

    /// A quiet filled capsule, 40 tall, answering to 44.
    private func actionButton(_ label: String, system: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Label(LocalizedStringKey(label), systemImage: system)
                .font(.ody(.subheadline, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(theme.fg.opacity(0.08), in: Capsule())
                .foregroundStyle(theme.fg)
                .frame(minHeight: Spacing.tapTarget)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func relative(_ iso: String) -> String {
        guard let t = ISODate.parse(iso) else { return iso }
        let f = RelativeDateTimeFormatter(); f.locale = LocalizationManager.shared.locale
        return f.localizedString(for: Date(timeIntervalSince1970: t), relativeTo: Date())
    }
}
