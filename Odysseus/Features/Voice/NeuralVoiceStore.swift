import Foundation
import SwiftUI
import FluidAudio

/// Tracks the PocketTTS language packs sitting on disk so the user can see what
/// they cost and delete them.
///
/// FluidAudio downloads each pack (~550 MB) into its own cache under Application
/// Support and never exposes a delete or a size — try enough languages and the
/// app quietly owns several gigabytes with no way to reclaim them.
///
/// Packs are found by **scanning for a directory named after the pack** rather
/// than rebuilding FluidAudio's `<cache>/Models/<repo>/v2.1/<lang>` layout: that
/// path is an upstream implementation detail (it already moved from v2 to v2.1),
/// and a stale hard-coded path would silently report "nothing installed" while
/// gigabytes stayed on disk.
@MainActor
final class NeuralVoiceStore: ObservableObject {
    static let shared = NeuralVoiceStore()

    struct Pack: Identifiable, Hashable {
        let language: PocketTtsLanguage
        let url: URL
        let bytes: Int64
        var id: String { language.rawValue }
    }

    @Published private(set) var packs: [Pack] = []
    @Published private(set) var scanning = false

    private init() {}

    var totalBytes: Int64 { packs.reduce(0) { $0 + $1.bytes } }

    /// Human label for a pack, in the app's language ("Português", "Deutsch"…),
    /// falling back to the raw upstream id for anything unmapped.
    static func label(_ pack: PocketTtsLanguage) -> String {
        let match = AppLanguage.allCases.first { SpeechManager.pocketPack(for: $0) == pack }
        return match?.nativeName ?? pack.rawValue
    }

    /// Rescans the cache. Sizing walks a multi-GB tree, so it runs off the main
    /// actor and only the result comes back.
    func refresh() {
        guard !scanning else { return }
        scanning = true
        Task {
            let found = await Self.scan()
            self.packs = found
            self.scanning = false
        }
    }

    /// Deletes a pack's files and forgets it in-memory if it was the loaded one.
    func delete(_ pack: Pack) {
        try? FileManager.default.removeItem(at: pack.url)
        packs.removeAll { $0.id == pack.id }
        SpeechManager.shared.forgetPack(pack.language)
    }

    // MARK: - Scanning

    private nonisolated static func cacheRoot() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("fluidaudio", isDirectory: true)
    }

    /// FluidAudio creates its own cache and never marks it, so ~550 MB per
    /// language pack would otherwise ride along in the user's iCloud backup.
    /// Idempotent — called whenever a pack is about to be loaded.
    nonisolated static func excludeCacheFromBackup() {
        guard let root = cacheRoot(), FileManager.default.fileExists(atPath: root.path) else { return }
        ModelDownloadManager.excludeFromBackup(root)
    }

    private nonisolated static func scan() async -> [Pack] {
        await Task.detached(priority: .utility) { () -> [Pack] in
            let fm = FileManager.default
            guard let root = cacheRoot(), fm.fileExists(atPath: root.path) else { return [] }
            let wanted = Dictionary(uniqueKeysWithValues:
                PocketTtsLanguage.allCases.map { ($0.rawValue, $0) })

            var out: [Pack] = []
            guard let walker = fm.enumerator(at: root,
                                             includingPropertiesForKeys: [.isDirectoryKey],
                                             options: [.skipsHiddenFiles]) else { return [] }
            for case let url as URL in walker {
                guard let lang = wanted[url.lastPathComponent],
                      (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                else { continue }
                walker.skipDescendants()   // don't walk into it twice
                out.append(Pack(language: lang, url: url, bytes: directorySize(url)))
            }
            return out.sorted { $0.language.rawValue < $1.language.rawValue }
        }.value
    }

    /// Bytes actually occupied (allocated size, so sparse/compressed files and
    /// block rounding are reported the way Settings › Storage would).
    private nonisolated static func directorySize(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }
        var total: Int64 = 0
        for case let f as URL in walker {
            guard let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }
}
