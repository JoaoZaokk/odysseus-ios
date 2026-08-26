import Foundation

/// Console tracing for the hands-free voice loop.
///
/// Xcode's debugger shows breakpoints and variables but nothing about *audio*:
/// it can't say that the mic went hot, that the barge-in gate was crossed, or
/// that echo cancellation quietly failed to engage. Those are exactly the things
/// that break here, and they only break on a physical device with a speaker, so
/// they have to be traced from inside the app.
///
/// Every line is prefixed `[voice]` and stamped with seconds since launch, so a
/// session reads as a timeline in Xcode's console. Filter the console on
/// `[voice]` to see only this.
///
/// DEBUG only — compiled out of Release entirely, so nothing about the user's
/// microphone is ever printed in a shipped build.
enum VoiceLog {
    /// Set false from the debugger to silence the stream without rebuilding.
    nonisolated(unsafe) static var enabled = true

    private static let start = Date()

    static func log(_ tag: String, _ message: @autoclosure () -> String = "") {
        #if DEBUG
        guard enabled else { return }
        let t = String(format: "%8.3f", Date().timeIntervalSince(start))
        let m = message()
        print("[voice \(t)] \(tag)\(m.isEmpty ? "" : " — \(m)")")
        #endif
    }

    /// Audio metrics are printed from the render callback at ~23 Hz, which is
    /// unreadable and wasteful; this throttles a tag to one line per interval.
    private final class Throttle: @unchecked Sendable {
        private var last: [String: Date] = [:]
        private let lock = NSLock()
        func allow(_ key: String, every seconds: TimeInterval) -> Bool {
            lock.lock(); defer { lock.unlock() }
            let now = Date()
            if let l = last[key], now.timeIntervalSince(l) < seconds { return false }
            last[key] = now
            return true
        }
    }
    private static let throttle = Throttle()

    static func metered(_ tag: String, every seconds: TimeInterval = 0.5,
                        _ message: @autoclosure () -> String) {
        #if DEBUG
        guard enabled, throttle.allow(tag, every: seconds) else { return }
        log(tag, message())
        #endif
    }

    /// Formats a 0…1 level as a bar, so a glance at the console shows the shape
    /// of what the mic heard instead of a column of decimals.
    static func bar(_ v: Float, width: Int = 20) -> String {
        let n = max(0, min(width, Int((v * Float(width) * 4).rounded())))
        return String(repeating: "█", count: n) + String(repeating: "·", count: width - n)
    }
}
