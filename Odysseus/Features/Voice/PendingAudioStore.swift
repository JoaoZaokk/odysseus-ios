import Foundation

/// Minimal WAV (PCM 16-bit mono) encode/decode, shared by the upload path and
/// the pending-audio store.
enum WAV {
    static func encode(_ frames: [Float], sampleRate: Int) -> Data {
        let channels = 1, bits = 16
        let blockAlign = channels * bits / 8
        let byteRate = sampleRate * blockAlign
        let dataSize = frames.count * blockAlign
        func u32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func u16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        var d = Data(capacity: 44 + dataSize)
        d.append(Data("RIFF".utf8)); d.append(u32(UInt32(36 + dataSize))); d.append(Data("WAVE".utf8))
        d.append(Data("fmt ".utf8)); d.append(u32(16)); d.append(u16(1)); d.append(u16(UInt16(channels)))
        d.append(u32(UInt32(sampleRate))); d.append(u32(UInt32(byteRate)))
        d.append(u16(UInt16(blockAlign))); d.append(u16(UInt16(bits)))
        d.append(Data("data".utf8)); d.append(u32(UInt32(dataSize)))
        var pcm = [Int16](repeating: 0, count: frames.count)
        for i in frames.indices { pcm[i] = Int16(max(-1, min(1, frames[i])) * 32767) }
        pcm.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }

    /// Reads back what `encode` wrote (16-bit PCM mono). Returns nil for anything else.
    static func decode(_ d: Data) -> (frames: [Float], sampleRate: Int)? {
        guard d.count > 44, String(data: d[0..<4], encoding: .ascii) == "RIFF",
              String(data: d[8..<12], encoding: .ascii) == "WAVE" else { return nil }
        var pos = 12
        var rate = 0, channels = 0, bits = 0
        while pos + 8 <= d.count {
            let id = String(data: d[pos..<pos + 4], encoding: .ascii) ?? ""
            let size = Int(d[pos + 4..<pos + 8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
            let body = pos + 8
            if id == "fmt ", body + 16 <= d.count {
                channels = Int(d[body + 2..<body + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }.littleEndian)
                rate = Int(d[body + 4..<body + 8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
                bits = Int(d[body + 14..<body + 16].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }.littleEndian)
            } else if id == "data" {
                guard channels == 1, bits == 16, rate > 0 else { return nil }
                let end = min(d.count, body + size)
                let n = (end - body) / 2
                var frames = [Float](repeating: 0, count: n)
                d[body..<body + n * 2].withUnsafeBytes { raw in
                    let p = raw.bindMemory(to: Int16.self)
                    for i in 0..<n { frames[i] = Float(Int16(littleEndian: p[i])) / 32767 }
                }
                return (frames, rate)
            }
            pos = body + size + (size & 1)
        }
        return nil
    }
}

/// Recordings that were finished but not yet turned into text, kept on disk so
/// that a process death during transcription — the 1.6 GB model that jetsam
/// kills, a watchdog during a long load, a dropped connection to the server —
/// costs a retry instead of the words themselves. The Redoma pattern: the file
/// is written *before* any engine is touched, and "pending" is derived from the
/// file's existence, never from a flag that could be half-written.
///
/// Apple's native recognizer is the declared exception: it consumes the mic
/// stream directly and produces partials while recording, so there is no raw
/// audio to save and a death loses less.
enum PendingAudioStore {
    struct Pending: Codable, Identifiable, Equatable, Sendable {
        var id: String
        var at: Date
        var seconds: Double
        /// `STTEngine.rawValue` at recording time — the engine the user chose
        /// for *this* take. Resuming with whatever is selected later could send
        /// a recording made for the on-device model to a server.
        var engine: String
        var modelID: String
        var language: String?
        /// Loads attempted since the file was written; bumped and persisted
        /// BEFORE the engine loads so a crash-on-load cannot loop forever.
        var attempts: Int
    }

    static let maxAge: TimeInterval = 7 * 24 * 3600
    static let maxFiles = 5
    static let sampleRate = 16_000

    static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("voice-pending", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        ModelDownloadManager.excludeFromBackup(d)
        return d
    }

    /// Atomic: `.part` then rename, so a kill mid-write never leaves a truncated
    /// take that the next launch would announce as a real recording.
    @discardableResult
    static func save(frames: [Float], engine: String, modelID: String, language: String?, in dir: URL? = nil) -> Pending? {
        let dir = dir ?? directory()
        let id = UUID().uuidString.lowercased()
        let part = dir.appendingPathComponent("\(id).wav.part")
        let final = dir.appendingPathComponent("\(id).wav")
        do {
            try WAV.encode(frames, sampleRate: sampleRate).write(to: part, options: [.atomic])
            try FileManager.default.moveItem(at: part, to: final)
        } catch {
            try? FileManager.default.removeItem(at: part)
            return nil
        }
        let p = Pending(id: id, at: Date(), seconds: Double(frames.count) / Double(sampleRate),
                        engine: engine, modelID: modelID, language: language, attempts: 0)
        write(p, in: dir)
        return p
    }

    static func write(_ p: Pending, in dir: URL? = nil) {
        let dir = dir ?? directory()
        if let d = try? JSONEncoder().encode(p) {
            try? d.write(to: dir.appendingPathComponent("\(p.id).json"), options: [.atomic])
        }
    }

    /// Oldest first. A .wav without a sidecar is still offered (duration from the
    /// header); a sidecar without a .wav is deleted.
    static func list(in dir: URL? = nil) -> [Pending] {
        let dir = dir ?? directory()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let wavs = Set(names.filter { $0.hasSuffix(".wav") }.map { String($0.dropLast(4)) })
        var out: [Pending] = []
        for id in wavs {
            let side = dir.appendingPathComponent("\(id).json")
            if let d = try? Data(contentsOf: side), let p = try? JSONDecoder().decode(Pending.self, from: d) {
                out.append(p)
            } else {
                let wav = dir.appendingPathComponent("\(id).wav")
                let size = (try? wav.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let created = (try? wav.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                out.append(Pending(id: id, at: created, seconds: Double(max(0, size - 44)) / Double(2 * sampleRate),
                                   engine: STTEngine.model.rawValue, modelID: "", language: nil, attempts: 0))
            }
        }
        for n in names where n.hasSuffix(".json") && !wavs.contains(String(n.dropLast(5))) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(n))
        }
        return out.sorted { $0.at < $1.at }
    }

    static func frames(of p: Pending, in dir: URL? = nil) -> [Float]? {
        let dir = dir ?? directory()
        guard let d = try? Data(contentsOf: dir.appendingPathComponent("\(p.id).wav")), let w = WAV.decode(d) else { return nil }
        return w.frames
    }

    static func delete(_ p: Pending, in dir: URL? = nil) {
        let dir = dir ?? directory()
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(p.id).wav"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(p.id).json"))
    }

    /// Bumps and persists the attempt counter; returns the updated record.
    static func bumpAttempts(_ p: Pending, in dir: URL? = nil) -> Pending {
        var q = p; q.attempts += 1
        write(q, in: dir)
        return q
    }

    /// Drops takes older than a week and everything beyond the newest five.
    static func purge(now: Date = Date(), in dir: URL? = nil) {
        let all = list(in: dir)
        for p in all where now.timeIntervalSince(p.at) > maxAge { delete(p, in: dir) }
        let fresh = list(in: dir)
        for p in fresh.dropLast(maxFiles) { delete(p, in: dir) }
    }
}
