import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Animated background patterns

/// A lightweight animated backdrop drawn with `Canvas` + `TimelineView`. Rendered
/// as a faint, non-interactive overlay so it reads as ambient motion without
/// hurting legibility. Mirrors the spirit of the web app's background effects.
struct AnimatedBackground: View {
    let pattern: BackgroundPattern
    var tint: Color

    private let particles: [Particle]

    init(pattern: BackgroundPattern, tint: Color) {
        self.pattern = pattern
        self.tint = tint
        var rng = SeededRNG(seed: 42)
        let n: Int
        switch pattern {
        case .none: n = 0
        case .stars: n = 70
        case .rain: n = 60
        case .embers: n = 45
        case .petals: n = 28
        }
        particles = (0..<n).map { _ in
            Particle(x: Double.random(in: 0...1, using: &rng),
                     y: Double.random(in: 0...1, using: &rng),
                     speed: Double.random(in: 0.3...1.0, using: &rng),
                     phase: Double.random(in: 0...6.28, using: &rng),
                     size: Double.random(in: 0.4...1.0, using: &rng),
                     drift: Double.random(in: -0.5...0.5, using: &rng))
        }
    }

    var body: some View {
        if pattern == .none {
            Color.clear
        } else {
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    for p in particles { draw(p, in: &ctx, size: size, t: t) }
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }

    private func draw(_ p: Particle, in ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width, h = size.height
        switch pattern {
        case .none: return
        case .stars:
            // Pronounced twinkle: `s²` makes each star spend more time dim and
            // snap bright, with a low floor so it clearly fades out (not always-on).
            // Per-star speed varies the blink rate across the field.
            let s = 0.5 + 0.5 * sin(t * (0.7 + p.speed * 1.8) + p.phase)
            let twinkle = 0.05 + 0.95 * (s * s)
            let r = 1.6 + p.size * 2.6
            let c = CGPoint(x: p.x * w, y: p.y * h)
            let halo = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: halo), with: .color(tint.opacity(twinkle * 0.28)))
            let core = CGRect(x: c.x - r / 2, y: c.y - r / 2, width: r, height: r)
            ctx.fill(Path(ellipseIn: core), with: .color(tint.opacity(twinkle)))
        case .rain:
            let yy = (p.y + t * (0.08 + p.speed * 0.18)).truncatingRemainder(dividingBy: 1)
            let x = p.x * w
            let y = yy * h
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + p.drift * 4, y: y + 10 + p.size * 12))
            ctx.stroke(path, with: .color(tint.opacity(0.22)), lineWidth: 0.8 + p.size * 0.8)
        case .embers:
            let prog = (p.y + t * (0.04 + p.speed * 0.12)).truncatingRemainder(dividingBy: 1)
            let y = (1 - prog) * h
            let x = (p.x + sin(t * 0.4 + p.phase) * 0.02) * w
            let r = 1.2 + p.size * 2.2
            let rect = CGRect(x: x, y: y, width: r, height: r)
            let fade = sin(prog * .pi)   // fade in/out over the rise
            ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(0.45 * fade)))
        case .petals:
            let prog = (p.y + t * (0.03 + p.speed * 0.08)).truncatingRemainder(dividingBy: 1)
            let y = prog * h
            let x = (p.x + sin(t * 0.5 + p.phase) * 0.05) * w
            let r = 3 + p.size * 5
            let rect = CGRect(x: x, y: y, width: r, height: r * 0.7)
            ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(0.18)))
        }
    }
}

private struct Particle {
    let x, y, speed, phase, size, drift: Double
}

/// Tiny deterministic RNG so the particle field is stable across redraws.
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 2862933555777941757 &+ 3037000493 }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}

// MARK: - macOS translucency backdrop

#if os(macOS)
/// Vibrancy backdrop that lets the desktop show through when "transparência" is on.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isOpaque = false
            w.backgroundColor = .clear
        }
    }
}
#endif
