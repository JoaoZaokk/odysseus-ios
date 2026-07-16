import SwiftUI

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var events: [CalendarEvent] = []
    @Published var calendars: [CalendarInfo] = []
    @Published var loading = false
    @Published var parsing = false
    @Published var error: String?

    private let api: APIClient
    init(api: APIClient) { self.api = api }

    var defaultCalendarHref: String? { calendars.first?.href }

    /// Events grouped by day, sorted chronologically.
    var grouped: [DayGroup] {
        let withDay = events.filter { $0.dayKey != nil }
        let buckets: [Date: [CalendarEvent]] = Dictionary(grouping: withDay) { $0.dayKey! }
        var result: [DayGroup] = []
        for (day, evs) in buckets {
            let sorted = evs.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            result.append(DayGroup(day: day, events: sorted))
        }
        return result.sorted { $0.day < $1.day }
    }

    struct DayGroup: Identifiable {
        let day: Date
        let events: [CalendarEvent]
        var id: Date { day }
    }

    func load() async {
        loading = true; defer { loading = false }
        do {
            async let cals = api.calendars()
            let now = Date()
            let start = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            let end = Calendar.current.date(byAdding: .month, value: 3, to: now) ?? now
            async let evs = api.events(start: start, end: end)
            calendars = try await cals
            events = try await evs
            error = nil
        } catch is CancellationError {
            // view transition tore down the load — ignore
        } catch { self.error = msg(error) }
    }

    func quickAdd(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        parsing = true; error = nil; defer { parsing = false }
        do { try await api.quickParseEvent(t); await load() }
        catch { self.error = msg(error) }
    }

    func create(summary: String, start: Date, end: Date, allDay: Bool) async {
        guard let href = defaultCalendarHref else { error = "Nenhum calendário disponível"; return }
        // en_US_POSIX: without it the formatter inherits the DEVICE calendar and
        // digits — a Thai device (Buddhist calendar) writes "2569-07-16" into the
        // user's real CalDAV, fa/ar devices write non-ASCII digits.
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = allDay ? "yyyy-MM-dd" : "yyyy-MM-dd'T'HH:mm:ss"
        let payload = EventPayload(summary: summary, dtstart: f.string(from: start),
                                   dtend: f.string(from: end), all_day: allDay,
                                   calendar_href: href, location: nil, description: nil)
        do { try await api.createEvent(payload); await load() }
        catch { self.error = msg(error) }
    }

    func delete(_ ev: CalendarEvent) async {
        do { try await api.deleteEvent(ev.uid); events.removeAll { $0.uid == ev.uid } }
        catch { self.error = msg(error) }
    }

    private func msg(_ e: Error) -> String {
        (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
    }
}

struct CalendarView: View {
    @StateObject private var vm: CalendarViewModel
    @Environment(\.theme) private var theme
    @State private var quickText = ""
    @State private var showCreate = false
    @FocusState private var quickFocused: Bool

    init(app: AppState) { _vm = StateObject(wrappedValue: CalendarViewModel(api: app.api)) }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                quickAddBar
                content
            }
        }
        .screenChrome(title: "Calendário") {
        } trailing: {
            Button { showCreate = true } label: { Image(systemName: "plus") }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showCreate) {
            EventEditor { summary, start, end, allDay in
                Task { await vm.create(summary: summary, start: start, end: end, allDay: allDay) }
            }
        }
    }

    private var quickAddBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(theme.accent)
                TextField("Ex: reunião amanhã 14h", text: $quickText)
                    .font(.ody(.subheadline, design: .monospaced))
                    .foregroundStyle(theme.fg)
                    .focused($quickFocused)
                    .submitLabel(.go)
                    .onSubmit { add() }
                    .disabled(vm.parsing)
                if vm.parsing {
                    ProgressView().controlSize(.small).tint(theme.accent)
                } else if !quickText.isEmpty {
                    Button { add() } label: { Image(systemName: "arrow.up.circle.fill").foregroundStyle(theme.accent) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))

            if let err = vm.error {
                Text(err)
                    .font(.ody(size: 11, design: .monospaced))
                    .foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
        }
        .padding(12)
    }

    private func add() {
        let t = quickText; quickText = ""; quickFocused = false
        Task { await vm.quickAdd(t) }
    }

    @ViewBuilder
    private var content: some View {
        if vm.events.isEmpty && vm.loading {
            Spacer(); ProgressView().tint(theme.accent); Spacer()
        } else if vm.grouped.isEmpty {
            emptyState
        } else {
            List {
                ForEach(vm.grouped, id: \.day) { group in
                    Section {
                        ForEach(group.events) { ev in
                            eventRow(ev).listRowBackground(theme.bg)
                        }
                    } header: {
                        Text(LocalizedStringKey(dayLabel(group.day)))
                            .font(.ody(.caption, design: .monospaced))
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func eventRow(_ ev: CalendarEvent) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: (ev.color ?? "e06c75").replacingOccurrences(of: "#", with: "")))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(ev.summary)
                    .font(.ody(.subheadline, design: .monospaced))
                    .foregroundStyle(theme.fg)
                HStack(spacing: 8) {
                    Text(LocalizedStringKey(timeLabel(ev)))
                        .font(.ody(size: 11, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                    if !ev.location.isEmpty {
                        Label(ev.location, systemImage: "mappin")
                            .font(.ody(size: 11, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { Task { await vm.delete(ev) } } label: {
                Label("Apagar", systemImage: "trash")
            }
        }
    }

    private func timeLabel(_ ev: CalendarEvent) -> String {
        if ev.allDay { return "Dia todo" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = .current
        guard let s = ev.startDate else { return "" }
        let start = f.string(from: s)
        if let e = ev.endDate { return "\(start)–\(f.string(from: e))" }
        return start
    }

    private func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Hoje" }
        if cal.isDateInTomorrow(d) { return "Amanhã" }
        let f = DateFormatter(); f.locale = LocalizationManager.shared.locale
        // Locale-appropriate "weekday, day month" instead of a pt-only literal format.
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f.string(from: d).capitalized
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "calendar").font(.ody(size: 44)).foregroundStyle(theme.accent)
                Text("Nenhum evento")
                    .font(.ody(.headline, design: .monospaced)).foregroundStyle(theme.fg)
                Text("Escreva em linguagem natural acima\nou toque em + para criar.")
                    .font(.ody(.footnote, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
    }
}

struct EventEditor: View {
    let onSave: (String, Date, Date, Bool) -> Void
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var summary = ""
    @State private var allDay = false
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3600)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Título", text: $summary)
                        .font(.ody(.body, design: .monospaced))
                }
                Section {
                    Toggle("Dia inteiro", isOn: $allDay).tint(theme.accent)
                    DatePicker("Início", selection: $start,
                               displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                    if !allDay {
                        DatePicker("Fim", selection: $end, displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }
            .navigationTitle("Novo evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        onSave(summary, start, allDay ? start : end, allDay); dismiss()
                    }.disabled(summary.isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
        }
        .tint(theme.accent)
    }
}
