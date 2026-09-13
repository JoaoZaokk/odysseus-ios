import Foundation
#if os(iOS)
import os
#endif

/// The process's memory budget, the way the kernel sees it.
///
/// On iOS `os_proc_available_memory` answers "how many bytes can I still dirty
/// before jetsam kills me" — the exact ceiling a 1.6 GB Whisper checkpoint has
/// to fit under, and the number that was missing when the f16 turbo "crashed
/// with no error" (jetsam is a SIGKILL: no exception, no crash report). The
/// value is a snapshot; read it right before the allocation, never cache it.
/// macOS has no equivalent (API_UNAVAILABLE), so there only the physical total
/// is known and the gate is off.
enum MemoryBudget {
    static var availableBytes: Int64? {
        #if os(iOS)
        let v = os_proc_available_memory()
        return v == 0 ? nil : Int64(v)
        #else
        return nil
        #endif
    }

    static var physicalBytes: Int64 { Int64(ProcessInfo.processInfo.physicalMemory) }

    static var freeDiskBytes: Int64? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let v = try? base.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage
    }

    /// Whole megabytes, for breadcrumbs and labels ("412" not "412.3 MB").
    static func mb(_ bytes: Int64?) -> String {
        guard let bytes else { return "?" }
        return String(bytes / 1_000_000)
    }

    static func human(_ bytes: Int64?) -> String {
        guard let bytes else { return "?" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}
