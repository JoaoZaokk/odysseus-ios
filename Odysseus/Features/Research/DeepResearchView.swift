import SwiftUI

@MainActor
final class DeepResearchVM: ObservableObject {
    @Published var prompt = ""
    @Published var mode = "auto"
    @Published var rounds = "Auto"
    @Published var format = "Auto"
    @Published var searchEngine = "Default"
    @Published var endpointId = ""        // "" = Default
    @Published var model = ""             // "" = Default
    @Published var endpoints: [ModelEndpoint] = []
    @Published var past: [ResearchJob] = []

    static let modes: [(String, String)] = [
        ("auto", "Auto"), ("product", "Product"), ("compare", "Compare"),
        ("howto", "How-to"), ("factcheck", "Fact-check"),
    ]
    static let roundsOpts = ["Auto", "1", "2", "3", "4", "5"]
    static let formatOpts = ["Auto", "Resumo", "Detalhado", "Tabela", "Bullet points"]
    static let engineOpts = ["Default", "SearXNG", "DuckDuckGo", "Brave", "Tavily"]

    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func load() async {
        endpoints = (try? await api.modelEndpoints()) ?? []
        await loadPast()
    }
    func loadPast() async { past = (try? await api.researchLibrary(limit: 20)) ?? [] }
    func models(_ id: String) -> [String] { endpoints.first { $0.id == id }?.models ?? [] }
    func endpointName(_ id: String) -> String { endpoints.first { $0.id == id }?.name ?? "Default" }

    /// "Auto" → nil (agent decides); otherwise the chosen integer.
    var maxRounds: Int? { Int(rounds) }

    var canStart: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Native Deep Research panel — mirrors the web "Research" composer (modes,
/// settings, Start + past research). Opens as a workspace column.
struct DeepResearchView: View {
    @StateObject private var vm: DeepResearchVM
    @StateObject private var runner = ResearchRunner()
    @ObservedObject var workspace: WorkspaceStore
    @Environment(\.theme) private var theme
    private let api: APIClient

    init(app: AppState, workspace: WorkspaceStore) {
        _vm = StateObject(wrappedValue: DeepResearchVM(api: app.api))
        self.workspace = workspace
        self.api = app.api
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Active research — the live animated node graph.
                    if let run = runner.run {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text("Active").font(.ody(.headline, design: .monospaced).weight(.semibold)).foregroundStyle(theme.fg)
                                if run.isPreview {
                                    Text("prévia").font(.ody(size: 9, design: .monospaced))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(theme.accent.opacity(0.18), in: Capsule())
                                        .foregroundStyle(theme.accent)
                                }
                            }
                            ResearchActiveCard(run: run, elapsed: runner.elapsed) { runner.close() }
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: run.rounds.count)
                    }

                    card {
                        Text("Research").font(.ody(.headline, design: .monospaced).weight(.semibold)).foregroundStyle(theme.fg)
                        Text("Pesquisa web multi-etapas com um agente LLM no loop.")
                            .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                        // Composer
                        TextEditor(text: $vm.prompt)
                            .font(.ody(.subheadline, design: .monospaced))
                            .foregroundStyle(theme.fg)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 90)
                            .padding(8)
                            .background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                            .overlay(alignment: .topLeading) {
                                if vm.prompt.isEmpty {
                                    Text("ex.: As teorias do colapso da Idade do Bronze e as evidências")
                                        .font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.secondaryText)
                                        .padding(.horizontal, 13).padding(.vertical, 16).allowsHitTesting(false)
                                }
                            }
                        // Modes
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(DeepResearchVM.modes, id: \.0) { m in
                                    chip(m.1, selected: vm.mode == m.0) { vm.mode = m.0 }
                                }
                            }
                        }
                        // Settings
                        settingsGrid
                        // Actions
                        HStack {
                            Spacer()
                            Button { start() } label: {
                                Label("Start", systemImage: "play.fill")
                                    .font(.ody(.subheadline, design: .monospaced).weight(.semibold))
                                    .padding(.horizontal, 16).padding(.vertical, 9)
                                    .foregroundStyle(.white)
                                    .background(vm.canStart ? theme.accent : theme.border, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain).disabled(!vm.canStart)
                        }
                    }

                    // Past research — real list from /api/research/library.
                    card {
                        HStack {
                            Text("Past research").font(.ody(.subheadline, design: .monospaced).weight(.semibold)).foregroundStyle(theme.fg)
                            Spacer()
                            Text("\(vm.past.count)").font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                        }
                        if vm.past.isEmpty {
                            Text("As pesquisas concluídas aparecem aqui. Toque em “Relatório visual” para abri-las ao lado.")
                                .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                        }
                        ForEach(vm.past) { job in
                            Divider().overlay(theme.border)
                            pastRow(job)
                        }
                    }
                }
                .padding(16)
            }
        }
        .screenChrome(title: "Deep Research")
        .task { await vm.load() }
    }

    private func start() {
        let p = vm.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        // Drives the live node graph from the real /api/research SSE stream.
        runner.start(api: api, query: p, maxRounds: vm.maxRounds, category: vm.mode)
        // Refresh the "Past research" list once the run completes.
        Task {
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await vm.loadPast()
                if runner.run?.status == "complete" || runner.run?.error == true { break }
            }
            await vm.loadPast()
        }
    }

    private var settingsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                labeledMenu("Rounds", value: vm.rounds, options: DeepResearchVM.roundsOpts) { vm.rounds = $0 }
                labeledMenu("Format", value: vm.format, options: DeepResearchVM.formatOpts) { vm.format = $0 }
            }
            HStack(spacing: 8) {
                labeledMenu("Search", value: vm.searchEngine, options: DeepResearchVM.engineOpts) { vm.searchEngine = $0 }
                labeledMenuRaw("Endpoint", value: vm.endpointId.isEmpty ? "Default" : vm.endpointName(vm.endpointId)) {
                    Button("Default") { vm.endpointId = ""; vm.model = "" }
                    ForEach(vm.endpoints.filter { $0.isEnabled }) { ep in Button(ep.name) { vm.endpointId = ep.id; vm.model = "" } }
                }
            }
            if !vm.endpointId.isEmpty {
                labeledMenuRaw("Model", value: vm.model.isEmpty ? "Default" : vm.model) {
                    Button("Default") { vm.model = "" }
                    ForEach(vm.models(vm.endpointId), id: \.self) { m in Button(m) { vm.model = m } }
                }
            }
        }
    }

    private func pastRow(_ job: ResearchJob) -> some View {
        let failed = (job.source_count ?? 0) == 0 || (job.status == "error")
        return VStack(alignment: .leading, spacing: 6) {
            Text(job.query).font(.ody(size: 12, design: .monospaced)).foregroundStyle(theme.fg).lineLimit(2)
            HStack(spacing: 8) {
                if let c = job.category, !c.isEmpty {
                    Text(c).foregroundStyle(theme.secondaryText)
                }
                Text(failed ? "no results" : "\(job.source_count ?? 0) sources")
                    .foregroundStyle(failed ? Color(hex: "e05a4a") : theme.secondaryText)
                if let r = job.rounds, r > 0 { Text("· \(r) rounds").foregroundStyle(theme.secondaryText) }
                if let d = job.duration, !d.isEmpty { Text("· \(d)").foregroundStyle(theme.secondaryText) }
            }
            .font(.ody(size: 10, design: .monospaced))
            HStack(spacing: 14) {
                Button { workspace.openVisualReport(id: job.id, title: job.query) } label: {
                    Label("Relatório visual", systemImage: "rectangle.righthalf.inset.filled")
                }
                .buttonStyle(.plain).foregroundStyle(theme.green)
                Spacer()
            }
            .font(.ody(size: 11, design: .monospaced))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Building blocks

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))
    }

    private func chip(_ label: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.ody(size: 12, design: .monospaced))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(selected ? .white : theme.secondaryText)
                .background(selected ? theme.accent : theme.bg, in: Capsule())
                .overlay(Capsule().stroke(theme.border, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func labeledMenu(_ label: String, value: String, options: [String], _ pick: @escaping (String) -> Void) -> some View {
        labeledMenuRaw(label, value: value) { ForEach(options, id: \.self) { o in Button(o) { pick(o) } } }
    }

    private func labeledMenuRaw<M: View>(_ label: String, value: String, @ViewBuilder _ menu: () -> M) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.ody(size: 9, design: .monospaced)).foregroundStyle(theme.secondaryText)
            Menu { menu() } label: {
                HStack {
                    Text(value).font(.ody(size: 12, design: .monospaced)).foregroundStyle(theme.fg).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.ody(size: 8)).foregroundStyle(theme.secondaryText)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A research's "Visual Report" opened as a side column — the server report
/// HTML parsed and rendered 100% natively (no WebView).
struct VisualReportView: View {
    let app: AppState
    let reportID: String
    let title: String
    @Environment(\.theme) private var theme
    @State private var report: ResearchReport?
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            if loading {
                ProgressView().tint(theme.accent)
            } else if let report {
                content(report)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: failed ? "exclamationmark.triangle" : "doc.richtext")
                        .font(.ody(size: 34)).foregroundStyle(theme.accent)
                    Text(failed ? "Não consegui carregar o relatório." : "Relatório vazio.")
                        .font(.ody(size: 12, design: .monospaced)).foregroundStyle(theme.secondaryText)
                }
            }
        }
        .screenChrome(title: "Relatório")
        .task(id: reportID) { await load() }
    }

    private func load() async {
        loading = true; failed = false
        do {
            let html = try await app.api.researchReportHTML(reportID)
            // Parse off the main thread so a heavy report never freezes the UI.
            let parsed = await Task.detached(priority: .userInitiated) {
                ReportParser.parse(html)
            }.value
            report = parsed.blocks.isEmpty && parsed.sources.isEmpty ? nil : parsed
        } catch {
            failed = true; report = nil
        }
        loading = false
    }

    @ViewBuilder private func content(_ r: ResearchReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Hero
                Text(r.title).font(.ody(.title2, design: .monospaced, weight: .bold)).foregroundStyle(theme.fg)
                if let s = r.subtitle, !s.isEmpty {
                    Text(s).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.secondaryText)
                }
                if !r.stats.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(r.stats.enumerated()), id: \.offset) { _, st in
                            VStack(spacing: 1) {
                                Text(st.value).font(.ody(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(theme.accent)
                                Text(st.label.uppercased()).font(.ody(size: 8, design: .monospaced)).foregroundStyle(theme.secondaryText)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(theme.panel, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                Divider().overlay(theme.border)

                // Body blocks
                ForEach(r.blocks) { block in blockView(block) }

                // Sources
                if !r.sources.isEmpty {
                    Divider().overlay(theme.border)
                    Text("Fontes (\(r.sources.count))")
                        .font(.ody(.headline, design: .monospaced, weight: .semibold)).foregroundStyle(theme.fg)
                    ForEach(r.sources) { sourceRow($0) }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func blockView(_ block: ReportBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(.ody(level == 2 ? .title3 : .headline, design: .monospaced, weight: .semibold))
                .foregroundStyle(theme.fg)
                .padding(.top, level == 2 ? 8 : 2)
        case .paragraph(let text):
            Text(text).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
        case .image(let url):
            AsyncImage(url: URL(string: url)) { img in
                img.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 10).fill(theme.panel).frame(height: 120)
                    .overlay(ProgressView().tint(theme.accent))
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1))
        case .table(let headers, let rows):
            reportTable(headers, rows)
        }
    }

    private func reportTable(_ headers: [String], _ rows: [[String]]) -> some View {
        let cols = max(headers.count, rows.map(\.count).max() ?? 0)
        return VStack(spacing: 0) {
            if !headers.isEmpty {
                tableRow(headers, cols: cols, header: true)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                tableRow(row, cols: cols, header: false, zebra: i % 2 == 1)
            }
        }
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }

    private func tableRow(_ cells: [String], cols: Int, header: Bool, zebra: Bool = false) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<cols, id: \.self) { c in
                Text(c < cells.count ? cells[c] : "")
                    .font(.ody(size: 11, weight: header ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(header ? theme.accent : theme.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                if c < cols - 1 { Rectangle().fill(theme.border).frame(width: 1) }
            }
        }
        .background(header ? theme.accent.opacity(0.10) : (zebra ? theme.bg.opacity(0.4) : .clear))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private func sourceRow(_ s: ReportSource) -> some View {
        Link(destination: URL(string: s.url) ?? URL(string: "https://")!) {
            HStack(alignment: .top, spacing: 8) {
                Text(s.num).font(.ody(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.accent).frame(width: 22, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title).font(.ody(size: 12, design: .monospaced)).foregroundStyle(theme.fg)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text(s.domain).font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right.square").font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
