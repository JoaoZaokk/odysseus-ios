import SwiftUI

// MARK: - Model

struct ResearchRound: Identifiable, Equatable {
    let id = UUID()
    let index: Int      // 1-based → "R1", "R2"
    var sources: Int    // source circles fanning around the round node
}

struct ResearchRun: Equatable {
    var query: String
    var rounds: [ResearchRound] = []
    var status: String = "planning strategy"   // planning / searching / comparison / warning
    var error: Bool = false
    var isPreview: Bool = false
    var sourcesTotal: Int { rounds.reduce(0) { $0 + $1.sources } }
    var roundCount: Int { rounds.count }
}

// MARK: - Animated node graph (Canvas)

/// The orange node graph: a central query node, round nodes (R1, R2…) fanning up,
/// each crowned with small source circles. Mirrors the web's research animation.
struct ResearchGraph: View {
    let run: ResearchRun
    @Environment(\.theme) private var theme

    // Fixed fan angles per round (degrees, 0=right, -90=up).
    private let fan: [Double] = [-90, -42, -138, -18, -162, -66, -114]

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                draw(&ctx, size: size, t: tl.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        let accent = run.error ? Color(hex: "e05a4a") : theme.accent
        let cx = size.width / 2
        let cy = size.height * 0.72
        let center = CGPoint(x: cx, y: cy)
        let R = min(size.width, size.height) * 0.42

        // Rounds + their sources
        for (i, round) in run.rounds.enumerated() {
            let ang = (fan[i % fan.count]) * .pi / 180
            let p = CGPoint(x: cx + cos(ang) * R, y: cy + sin(ang) * R)
            line(&ctx, center, p, accent.opacity(0.35), 1)

            // source circles fan outward from the round node
            if round.sources > 0 {
                let span = Double.pi * 0.9
                for s in 0..<round.sources {
                    let frac = round.sources == 1 ? 0.5 : Double(s) / Double(round.sources - 1)
                    let sa = ang - span / 2 + span * frac
                    let sr = R * 0.42
                    let sp = CGPoint(x: p.x + cos(sa) * sr, y: p.y + sin(sa) * sr)
                    line(&ctx, p, sp, accent.opacity(0.22), 0.8)
                    ring(&ctx, sp, 6, accent.opacity(0.8), fill: theme.bg, lw: 1.4)
                }
            }
            // round node (ring with dark center) + label
            ring(&ctx, p, 13, accent, fill: theme.bg, lw: 2.2)
            label(&ctx, "R\(round.index)", at: CGPoint(x: p.x + 22, y: p.y - 14), color: theme.secondaryText)
        }

        // Central query node — gently pulsing
        let pulse = 1 + 0.06 * sin(t * 2.2)
        let cr = 22.0 * pulse
        ctx.fill(Path(ellipseIn: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2)),
                 with: .color(accent))
        // halo
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - cr - 4, y: cy - cr - 4, width: (cr + 4) * 2, height: (cr + 4) * 2)),
                   with: .color(accent.opacity(0.25)), lineWidth: 2)

        // Query caption under the center
        label(&ctx, truncate(run.query, 26), at: CGPoint(x: cx, y: cy + cr + 18),
              color: theme.fg, centered: true, mono: true)
    }

    private func line(_ ctx: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ c: Color, _ w: CGFloat) {
        var p = Path(); p.move(to: a); p.addLine(to: b)
        ctx.stroke(p, with: .color(c), lineWidth: w)
    }
    private func ring(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ color: Color, fill: Color, lw: CGFloat) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(fill))
        ctx.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: lw)
    }
    private func label(_ ctx: inout GraphicsContext, _ s: String, at p: CGPoint, color: Color, centered: Bool = false, mono: Bool = false) {
        let text = Text(s).font(.system(size: mono ? 11 : 12, design: mono ? .monospaced : .default)).foregroundColor(color)
        ctx.draw(text, at: p, anchor: centered ? .center : .leading)
    }
    private func truncate(_ s: String, _ n: Int) -> String { s.count <= n ? s : String(s.prefix(n)) + "…" }
}

// MARK: - Active research card

struct ResearchActiveCard: View {
    let run: ResearchRun
    let elapsed: String
    var onClose: (() -> Void)?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(run.query).font(.ody(.subheadline, design: .monospaced, weight: .semibold))
                    .foregroundStyle(theme.fg).lineLimit(1)
                Spacer()
                Text(elapsed).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
                if let onClose {
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(theme.secondaryText).font(.ody(size: 11))
                }
            }
            Text(statusTitle).font(.ody(size: 12, design: .monospaced))
                .foregroundStyle(run.error ? Color(hex: "e05a4a") : theme.secondaryText)

            ResearchGraph(run: run)
                .frame(height: 230)
                .background(
                    RadialGradient(colors: [theme.accent.opacity(run.error ? 0.0 : 0.10), .clear],
                                   center: .bottom, startRadius: 2, endRadius: 260)
                )

            Text("\(run.error ? "warning" : run.status)  ·  round \(run.roundCount)  ·  \(run.sourcesTotal) sources  ·  \(elapsed)")
                .font(.ody(size: 11, design: .monospaced))
                .foregroundStyle(run.error ? Color(hex: "e05a4a") : theme.accent)
        }
        .padding(14)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(run.error ? Color(hex: "e05a4a") : theme.border, lineWidth: run.error ? 1.6 : 1)
        )
    }

    private var statusTitle: String {
        if run.error { return "no results — tente reformular ou trocar o motor de busca." }
        if run.rounds.isEmpty { return "Planejando estratégia…" }
        return "Round \(run.roundCount): \(run.status.capitalized) (\(run.sourcesTotal) sources)"
    }
}

// MARK: - Preview driver (animates the graph until the real research API is wired)

@MainActor
final class ResearchRunner: ObservableObject {
    @Published var run: ResearchRun?
    @Published var elapsed = "00:00"
    private var task: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var start = Date()

    // MARK: - Live run (real /api/research/* stream)

    /// Starts a real research run and drives the graph from the SSE stream.
    func start(api: APIClient, query: String, maxRounds: Int?, category: String?) {
        cancel()
        start = Date()
        run = ResearchRun(query: query, status: "planning strategy", isPreview: false)
        startTimer()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let id = try await api.startResearch(query: query, maxRounds: maxRounds, category: category)
                var lastPhase = "planning"
                var lastTotalSources = 0
                for try await evt in api.researchStream(id) {
                    if Task.isCancelled { return }
                    self.apply(evt, lastPhase: &lastPhase, lastTotalSources: &lastTotalSources)
                    if self.run?.error == true { return }
                    if evt.final == true || evt.status == "done" || evt.status == "complete" {
                        // A finished run with no sources is the web's "no results" state.
                        if (self.run?.sourcesTotal ?? 0) == 0 {
                            self.run?.error = true; self.run?.status = "error"
                        } else {
                            self.run?.status = "complete"
                        }
                        return
                    }
                }
            } catch is CancellationError {
                // user closed the panel
            } catch {
                self.run?.error = true
                self.run?.status = "error"
            }
        }
    }

    /// Folds one stream event into the visual `ResearchRun`.
    private func apply(_ evt: ResearchEvent, lastPhase: inout String, lastTotalSources: inout Int) {
        guard run != nil else { return }
        if evt.status == "error" || evt.phase == "error" || evt.status == "cancelled" || evt.status == "not_found" {
            run?.error = true; run?.status = "error"; return
        }
        if let raw = evt.phase {
            run?.status = Self.label(raw)
            // A transition into "searching" marks a new round.
            if raw.hasPrefix("search") && !lastPhase.hasPrefix("search") {
                let n = (run?.rounds.count ?? 0) + 1
                run?.rounds.append(ResearchRound(index: n, sources: 0))
            }
            lastPhase = raw
        }
        // Distribute newly-found sources into the latest round node.
        if let total = evt.total_sources, total != lastTotalSources {
            if run?.rounds.isEmpty == true { run?.rounds.append(ResearchRound(index: 1, sources: 0)) }
            let delta = max(0, total - lastTotalSources)
            if delta > 0, var last = run?.rounds.last {
                last.sources += delta
                run?.rounds[(run!.rounds.count - 1)] = last
            }
            lastTotalSources = total
        }
    }

    /// Maps an internal phase key to the web's display label.
    static func label(_ phase: String) -> String {
        let p = phase.lowercased()
        if p.hasPrefix("prob") || p.hasPrefix("verif") { return "verifying model" }
        if p.hasPrefix("plan")   { return "planning strategy" }
        if p.hasPrefix("search") { return "searching" }
        if p.hasPrefix("read")   { return "reading sources" }
        if p.hasPrefix("analy")  { return "analyzing findings" }
        if p.hasPrefix("writ")   { return "writing report" }
        if p.hasPrefix("complet") || p == "done" { return "complete" }
        return phase
    }

    // MARK: - Preview (offline fallback / SwiftUI previews)

    func startPreview(query: String) {
        cancel()
        start = Date()
        run = ResearchRun(query: query, status: "planning strategy", isPreview: true)
        startTimer()
        task = Task {
            func sleep(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
            await sleep(1.3); guard !Task.isCancelled else { return }
            run?.status = "searching"; run?.rounds = [ResearchRound(index: 1, sources: 0)]
            for s in 1...6 { await sleep(0.32); guard !Task.isCancelled else { return }; run?.rounds[0].sources = s }
            await sleep(0.7); guard !Task.isCancelled else { return }
            run?.rounds.append(ResearchRound(index: 2, sources: 0))
            for s in 1...5 { await sleep(0.32); guard !Task.isCancelled else { return }; run?.rounds[1].sources = s }
            await sleep(0.7); run?.status = "comparison"
        }
    }

    func close() { cancel(); run = nil }

    private func cancel() { task?.cancel(); task = nil; timer?.cancel(); timer = nil }

    private func startTimer() {
        timer = Task {
            while !Task.isCancelled {
                let e = Int(Date().timeIntervalSince(start))
                elapsed = String(format: "%02d:%02d", e / 60, e % 60)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}
