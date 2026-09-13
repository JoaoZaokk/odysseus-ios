import Foundation
#if canImport(MetricKit)
import MetricKit
#endif

/// Subscribes to MetricKit and turns what the system reports into spool
/// events: crashes and hangs (with their call-stack tree saved as a blob),
/// and the daily metrics' *exit* counts — `cumulativeMemoryResourceLimitExitCount`
/// is the only official trace a jetsam leaves. Payloads are persisted the
/// moment they arrive: `pastDiagnosticPayloads` is per-process and the spool
/// is what the Diagnostics screen and the uploader read.
///
/// Never runs in the simulator (MetricKit does not either).
final class MetricKitCollector: NSObject {
    static let shared = MetricKitCollector()
    private var started = false

    func start() {
        #if canImport(MetricKit) && !targetEnvironment(simulator)
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
        #endif
    }
}

#if canImport(MetricKit) && !targetEnvironment(simulator)
extension MetricKitCollector: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let store = DiagnosticsStore.shared
        for p in payloads {
            store.saveBlob(p.jsonRepresentation(), kind: "mx-diagnostic", at: p.timeStampEnd)
            for c in p.crashDiagnostics ?? [] {
                var props: [String: String] = [
                    "type": c.exceptionType.map { "\($0)" } ?? "?",
                    "code": c.exceptionCode.map { "\($0)" } ?? "?",
                    "signal": c.signal.map { "\($0)" } ?? "?",
                    "version": c.applicationVersion,
                    "end": ISO8601DateFormatter().string(from: p.timeStampEnd),
                ]
                if #available(iOS 17.0, macOS 14.0, *) {
                    props["reason"] = String((c.exceptionReason?.composedMessage ?? "").prefix(300))
                    props["termination"] = String((c.terminationReason ?? "").prefix(200))
                    props["vmRegion"] = String((c.virtualMemoryRegionInfo ?? "").prefix(200))
                }
                store.event("crash", props)
            }
            for h in p.hangDiagnostics ?? [] {
                store.event("hang", ["seconds": String(format: "%.1f", h.hangDuration.converted(to: .seconds).value),
                                     "version": h.applicationVersion])
            }
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        let store = DiagnosticsStore.shared
        for p in payloads {
            #if os(iOS)
            if let exits = p.applicationExitMetrics {
                let fg = exits.foregroundExitData
                let bg = exits.backgroundExitData
                store.event("app_exit.metrics", [
                    "fg.memoryLimit": String(fg.cumulativeMemoryResourceLimitExitCount),
                    "fg.abnormal": String(fg.cumulativeAbnormalExitCount),
                    "fg.badAccess": String(fg.cumulativeBadAccessExitCount),
                    "fg.illegal": String(fg.cumulativeIllegalInstructionExitCount),
                    "fg.watchdog": String(fg.cumulativeAppWatchdogExitCount),
                    "bg.memoryLimit": String(bg.cumulativeMemoryResourceLimitExitCount),
                    "bg.memoryPressure": String(bg.cumulativeMemoryPressureExitCount),
                    "end": ISO8601DateFormatter().string(from: p.timeStampEnd),
                ])
                if fg.cumulativeMemoryResourceLimitExitCount > 0 {
                    store.event("app_exit.memory_limit", ["count": String(fg.cumulativeMemoryResourceLimitExitCount)])
                }
            }
            #endif
            if let m = p.memoryMetrics {
                store.event("memory.metrics", [
                    "peakMB": String(Int(m.peakMemoryUsage.converted(to: .megabytes).value)),
                    "avgSuspendedMB": String(Int(m.averageSuspendedMemory.averageMeasurement.converted(to: .megabytes).value)),
                ])
            }
        }
    }
}
#endif

extension DiagnosticsStore {
    /// Raw MetricKit payloads, kept next to the spool (last 20).
    func saveBlob(_ data: Data, kind: String, at date: Date) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diagnostics/blobs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let name = "\(kind)-\(Int(date.timeIntervalSince1970)).json"
        try? data.write(to: base.appendingPathComponent(name), options: [.atomic])
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []).sorted()
        for old in files.dropLast(20) { try? FileManager.default.removeItem(at: base.appendingPathComponent(old)) }
    }
}
