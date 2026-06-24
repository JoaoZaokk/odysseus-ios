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
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
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
    var scheduleText: String {
        if (triggerType ?? "schedule") == "event" {
            return "Evento: \(triggerEvent ?? "?")"
        }
        switch schedule {
        case "cron": return "Cron: \(cronExpression ?? "?")"
        case "once": return "Uma vez \(scheduledTime ?? "")"
        case "daily": return "Diário \(scheduledTime ?? "")"
        case "hourly": return "De hora em hora"
        case "weekly": return "Semanal \(scheduledTime ?? "")"
        default: return scheduledTime.map { "Agendado \($0)" } ?? "Manual"
        }
    }
}

// MARK: - API

extension APIClient {
    func tasks() async throws -> [ScheduledTask] {
        decodeList(ScheduledTask.self, try await send(request("/api/tasks")))
    }
    func runTask(_ id: String) async throws { _ = try await send(request("/api/tasks/\(id)/run?force=true", method: "POST")) }
    func pauseTask(_ id: String) async throws { _ = try await send(request("/api/tasks/\(id)/pause", method: "POST")) }
    func resumeTask(_ id: String) async throws { _ = try await send(request("/api/tasks/\(id)/resume", method: "POST")) }
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
        catch is CancellationError {}
        catch { self.error = msg(error) }
    }
    func run(_ t: ScheduledTask) async {
        busyID = t.id; defer { busyID = nil }
        do { try await api.runTask(t.id) } catch { self.error = msg(error) }
    }
    func toggle(_ t: ScheduledTask) async {
        busyID = t.id; defer { busyID = nil }
        do {
            if t.isPaused { try await api.resumeTask(t.id) } else { try await api.pauseTask(t.id) }
            await load()
        } catch { self.error = msg(error) }
    }
    private func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? e.localizedDescription }
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
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.tasks.isEmpty && vm.loading {
            ProgressView().tint(theme.accent)
        } else if vm.tasks.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "checklist").font(.ody(size: 44)).foregroundStyle(theme.accent)
                Text("Sem tarefas").font(.ody(.headline, design: .monospaced)).foregroundStyle(theme.fg)
                Text("Agentes agendados do Odysseus aparecem aqui.")
                    .font(.ody(.footnote, design: .monospaced)).foregroundStyle(theme.secondaryText)
            }.padding(40)
        } else {
            List {
                ForEach(vm.tasks) { t in taskRow(t).listRowBackground(theme.bg) }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
        }
    }

    private func taskRow(_ t: ScheduledTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(t.isPaused ? theme.secondaryText : theme.green).frame(width: 8, height: 8)
                Text(t.name).font(.ody(.subheadline, design: .monospaced).weight(.semibold)).foregroundStyle(theme.fg)
                Spacer()
                if vm.busyID == t.id { ProgressView().controlSize(.small) }
            }
            Text(t.scheduleText).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
            HStack(spacing: 12) {
                if let last = t.lastRun { Label(relative(last), systemImage: "clock.arrow.circlepath").labelStyle(.titleAndIcon) }
                Label("\(t.runCount)x", systemImage: "repeat")
            }
            .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)

            HStack(spacing: 8) {
                actionButton(t.isPaused ? "Retomar" : "Pausar", system: t.isPaused ? "play.fill" : "pause.fill") {
                    Task { await vm.toggle(t) }
                }
                actionButton("Rodar agora", system: "bolt.fill") { Task { await vm.run(t) } }
            }
        }
        .padding(.vertical, 6)
    }

    private func actionButton(_ label: String, system: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Label(label, systemImage: system)
                .font(.ody(size: 11, design: .monospaced))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(theme.panel, in: Capsule())
                .overlay(Capsule().stroke(theme.border, lineWidth: 1))
                .foregroundStyle(theme.fg)
        }
        .buttonStyle(.plain)
    }

    private func relative(_ iso: String) -> String {
        guard let t = ISODate.parse(iso) else { return iso }
        let f = RelativeDateTimeFormatter(); f.locale = Locale(identifier: "pt_BR")
        return f.localizedString(for: Date(timeIntervalSince1970: t), relativeTo: Date())
    }
}
