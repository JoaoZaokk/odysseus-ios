import Foundation
import SwiftUI
import ZIPFoundation

/// Downloads and stores speech models **on the device** (no Mac involved).
/// Handles both the Whisper GGUF (.bin) and the optional CoreML encoder
/// (.mlmodelc, downloaded as a zip and unpacked next to the .bin so whisper.cpp
/// runs on the Neural Engine instead of the CPU). CoreML task ids are prefixed
/// with "ml:".
@MainActor
final class ModelDownloadManager: NSObject, ObservableObject {
    static let shared = ModelDownloadManager()

    @Published private(set) var installed: Set<String> = []
    @Published private(set) var coreMLInstalled: Set<String> = []
    @Published private(set) var progress: [String: Double] = [:]   // key: model id, or "ml:"+id
    @Published var error: String?

    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()
    private var tasks: [String: URLSessionDownloadTask] = [:]

    nonisolated static func modelsDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        excludeFromBackup(d)
        return d
    }

    /// Keeps re-downloadable model files out of iCloud/iTunes backups, per
    /// Apple's data-storage guidelines — otherwise every 500 MB checkpoint the
    /// user tries rides along in their backup forever. Marking the directory
    /// covers its whole subtree, and it's re-applied on each call so installs
    /// created before this existed get fixed too.
    nonisolated static func excludeFromBackup(_ url: URL) {
        var u = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? u.setResourceValues(values)
    }
    private let dir = ModelDownloadManager.modelsDir()

    override init() {
        super.init()
        refresh()
    }

    // MARK: - Paths / state

    func localURL(_ model: VoiceModel) -> URL { dir.appendingPathComponent("\(model.id)-\(model.filename)") }
    private func coreMLFolderURL(_ model: VoiceModel) -> URL {
        dir.appendingPathComponent(Self.coreMLFolderName(id: model.id, filename: model.filename))
    }
    nonisolated private static func coreMLFolderName(id: String, filename: String) -> String {
        let bin = "\(id)-\(filename)"                       // w-base-ggml-base.bin
        let stem = bin.hasSuffix(".bin") ? String(bin.dropLast(4)) : bin
        return "\(stem)-encoder.mlmodelc"                   // w-base-ggml-base-encoder.mlmodelc
    }

    func isInstalled(_ model: VoiceModel) -> Bool { installed.contains(model.id) }
    func isDownloading(_ model: VoiceModel) -> Bool { tasks[model.id] != nil }
    func coreMLAvailable(_ model: VoiceModel) -> Bool { VoiceCatalog.coreMLZipURL(forID: model.id) != nil }
    func hasCoreML(_ model: VoiceModel) -> Bool { coreMLInstalled.contains(model.id) }
    func coreMLProgress(_ model: VoiceModel) -> Double? { progress["ml:\(model.id)"] }
    func isDownloadingCoreML(_ model: VoiceModel) -> Bool { tasks["ml:\(model.id)"] != nil }

    func refresh() {
        let files = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        installed = Set(VoiceCatalog.all.filter { files.contains("\($0.id)-\($0.filename)") }.map(\.id))
        coreMLInstalled = Set(VoiceCatalog.all.filter { files.contains(Self.coreMLFolderName(id: $0.id, filename: $0.filename)) }.map(\.id))
    }

    // MARK: - GGUF model

    func download(_ model: VoiceModel) {
        guard tasks[model.id] == nil, !isInstalled(model) else { return }
        error = nil
        progress[model.id] = 0
        let task = session.downloadTask(with: model.url)
        task.taskDescription = model.id
        tasks[model.id] = task
        task.resume()
    }

    func cancel(_ model: VoiceModel) {
        tasks[model.id]?.cancel(); tasks[model.id] = nil; progress[model.id] = nil
    }

    func delete(_ model: VoiceModel) {
        try? FileManager.default.removeItem(at: localURL(model))
        installed.remove(model.id)
        deleteCoreML(model)   // the encoder is useless without the model
        // A user-added model has no catalog entry to fall back to — deleting the
        // file must also drop the registration, or the list keeps a dead row.
        if model.isCustom { CustomModels.remove(id: model.id) }
    }

    // MARK: - User-supplied model URLs

    enum AddError: LocalizedError {
        case notHTTPS, unreachable(String), noSpace(Int64), notAWhisperModel

        var errorDescription: String? {
            switch self {
            case .notHTTPS:
                return L("Use um link https.")
            case .unreachable(let why):
                return L("Não consegui acessar esse link: %@", why)
            case .noSpace(let need):
                return L("Espaço insuficiente: são necessários %@ livres.",
                         ByteCountFormatter.string(fromByteCount: need, countStyle: .file))
            case .notAWhisperModel:
                return L("Não parece um modelo Whisper ggml. Confira se o link aponta para o arquivo, não para a página.")
            }
        }
    }

    /// Normalizes a pasted link and starts the download.
    ///
    /// Rejects anything but https (App Transport Security blocks cleartext, and
    /// an unencrypted model download is trivially tamperable), and rewrites the
    /// Hugging Face *page* URL into the file URL — pasting the `/blob/` link is
    /// the single most common mistake and otherwise downloads an HTML page that
    /// only fails much later, at load time.
    func addCustomModel(from raw: String) async throws {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard var comps = URLComponents(string: text), let host = comps.host else {
            throw AddError.notHTTPS
        }
        guard comps.scheme?.lowercased() == "https" else { throw AddError.notHTTPS }
        if host.hasSuffix("huggingface.co"), let r = comps.path.range(of: "/blob/") {
            comps.path.replaceSubrange(r, with: "/resolve/")
        }
        guard let url = comps.url else { throw AddError.notHTTPS }

        let size = try await Self.probe(url)
        if size > 0, let free = Self.freeBytes(), free < size + 50_000_000 {
            throw AddError.noSpace(size)
        }

        let name = url.deletingPathExtension().lastPathComponent
        let entry = CustomVoiceModel(id: "u-\(UUID().uuidString.prefix(8))",
                                     name: name.isEmpty ? L("Modelo próprio") : name,
                                     urlString: url.absoluteString,
                                     bytes: size)
        CustomModels.add(entry)
        refresh()
        if let m = entry.model { download(m) }
    }

    /// HEAD for status + size. Servers that reject HEAD still get a chance:
    /// an unknown size only means we skip the free-space check.
    private static func probe(_ url: URL) async throws -> Int64 {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 20
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return 0 }
            if http.statusCode == 405 || http.statusCode == 501 { return 0 }   // HEAD unsupported
            guard (200..<300).contains(http.statusCode) else {
                throw AddError.unreachable("HTTP \(http.statusCode)")
            }
            return max(0, http.expectedContentLength)
        } catch let e as AddError {
            throw e
        } catch {
            throw AddError.unreachable(error.localizedDescription)
        }
    }

    private static func freeBytes() -> Int64? {
        let v = try? modelsDir().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage
    }

    /// whisper.cpp refuses anything whose first four bytes aren't its magic
    /// (`whisper.cpp:811`, `magic != 0x67676d6c`). Checking here means a wrong
    /// link — an HTML error page, a GGUF, an ONNX file — is caught and deleted
    /// at download time instead of surfacing as a failed transcription later.
    nonisolated static func isWhisperGGML(at url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 4), d.count == 4 else { return false }
        let magic = d.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return UInt32(littleEndian: magic) == 0x6767_6d6c
    }

    // MARK: - CoreML encoder

    func downloadCoreML(_ model: VoiceModel) {
        let key = "ml:\(model.id)"
        guard tasks[key] == nil, !hasCoreML(model),
              let url = VoiceCatalog.coreMLZipURL(forID: model.id) else { return }
        error = nil
        progress[key] = 0
        let task = session.downloadTask(with: url)
        task.taskDescription = key
        tasks[key] = task
        task.resume()
    }

    func cancelCoreML(_ model: VoiceModel) {
        let key = "ml:\(model.id)"
        tasks[key]?.cancel(); tasks[key] = nil; progress[key] = nil
    }

    func deleteCoreML(_ model: VoiceModel) {
        try? FileManager.default.removeItem(at: coreMLFolderURL(model))
        coreMLInstalled.remove(model.id)
    }

    func totalInstalledBytes() -> Int64 {
        VoiceCatalog.all.filter { installed.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }
}

extension ModelDownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite total: Int64) {
        guard let id = downloadTask.taskDescription, total > 0 else { return }
        let p = Double(totalBytesWritten) / Double(total)
        Task { @MainActor in self.progress[id] = p }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }

        if id.hasPrefix("ml:") {
            let modelID = String(id.dropFirst(3))
            guard let model = VoiceCatalog.all.first(where: { $0.id == modelID }) else { return }
            let ok = Self.unpackCoreML(zip: location, id: model.id, filename: model.filename)
            Task { @MainActor in
                self.tasks[id] = nil; self.progress[id] = nil
                if ok { self.coreMLInstalled.insert(modelID) }
                else { self.error = L("Falha ao descompactar o modelo Core ML.") }
            }
            return
        }

        guard let model = VoiceCatalog.all.first(where: { $0.id == id }) else { return }

        // Validate BEFORE installing. A CDN error page or a wrong-format file
        // arrives as a perfectly successful 200; without this it lands in place
        // and only fails later, when the user tries to dictate.
        guard Self.isWhisperGGML(at: location) else {
            try? FileManager.default.removeItem(at: location)
            Task { @MainActor in
                self.tasks[id] = nil; self.progress[id] = nil
                if model.isCustom { CustomModels.remove(id: id); self.refresh() }
                self.error = AddError.notAWhisperModel.errorDescription
            }
            return
        }

        let dest = Self.modelsDir().appendingPathComponent("\(model.id)-\(model.filename)")
        try? FileManager.default.removeItem(at: dest)
        let moved = (try? FileManager.default.moveItem(at: location, to: dest)) != nil
        Task { @MainActor in
            self.tasks[id] = nil; self.progress[id] = nil
            if moved { self.installed.insert(id) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError err: Error?) {
        guard let id = task.taskDescription else { return }
        Task { @MainActor in
            self.tasks[id] = nil; self.progress[id] = nil
            if let err, (err as? URLError)?.code != .cancelled { self.error = err.localizedDescription }
        }
    }

    /// Unzips the CoreML zip and moves the inner `.mlmodelc` folder to the path
    /// whisper.cpp derives from the .bin (`…-encoder.mlmodelc`).
    private nonisolated static func unpackCoreML(zip location: URL, id: String, filename: String) -> Bool {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("ml-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }
        do {
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            try fm.unzipItem(at: location, to: tmp)
        } catch { return false }

        // Find the .mlmodelc folder (top level or nested).
        var found: URL?
        if let en = fm.enumerator(at: tmp, includingPropertiesForKeys: nil) {
            for case let u as URL in en where u.pathExtension == "mlmodelc" { found = u; break }
        }
        guard let src = found else { return false }
        let dest = modelsDir().appendingPathComponent(coreMLFolderName(id: id, filename: filename))
        try? fm.removeItem(at: dest)
        return (try? fm.moveItem(at: src, to: dest)) != nil
    }
}
