import Foundation

// Read-only ComfyUI client. Talks directly to a user-configured ComfyUI server
// (e.g. http://host:8190) — NOT the Odysseus cookie session. Only GET endpoints
// are used here; image generation (`POST /prompt`) is intentionally not included
// in this phase. Verified live against ComfyUI 0.22.0 (2026-06-24).

struct ComfyGPU: Identifiable {
    let index: Int
    let name: String
    let vramTotal: Int64
    let vramFree: Int64
    var id: Int { index }
    var vramTotalGB: Double { Double(vramTotal) / 1e9 }
    var vramFreeGB: Double { Double(vramFree) / 1e9 }
}

struct ComfyStats {
    let os: String
    let comfyVersion: String
    let pythonVersion: String
    let pytorchVersion: String
    let ramTotal: Int64
    let ramFree: Int64
    let gpus: [ComfyGPU]
    var ramTotalGB: Double { Double(ramTotal) / 1e9 }
    var ramFreeGB: Double { Double(ramFree) / 1e9 }
    /// Largest single-GPU free VRAM — the cap for a single-GPU model load.
    var maxGPUFreeGB: Double { gpus.map(\.vramFreeGB).max() ?? 0 }
    /// Pooled free VRAM (rough upper bound for multi-GPU/sharded loads).
    var totalGPUFreeGB: Double { gpus.map(\.vramFreeGB).reduce(0, +) }
}

struct ComfyModels {
    var checkpoints: [String] = []
    var unets: [String] = []
    var loras: [String] = []
    var vae: [String] = []
    var clip: [String] = []
    var controlnet: [String] = []
    var total: Int { checkpoints.count + unets.count + loras.count + vae.count + clip.count + controlnet.count }
}

enum ComfyError: LocalizedError {
    case badURL, http(Int), decode, unreachable(String)
    var errorDescription: String? {
        switch self {
        case .badURL: return "URL inválida."
        case .http(let c): return "HTTP \(c)."
        case .decode: return "Resposta inesperada do ComfyUI."
        case .unreachable(let m): return "Sem conexão: \(m)"
        }
    }
}

struct ComfyUIClient {
    let baseURL: String
    var timeout: TimeInterval = 20

    private func url(_ path: String) throws -> URL {
        var s = baseURL.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { throw ComfyError.badURL }
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        // Reject anything that isn't a plain http(s) host (no file://, smuggled schemes).
        guard let u = URL(string: s + path), let host = u.host, !host.isEmpty,
              let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ComfyError.badURL
        }
        return u
    }

    private func getJSON(_ path: String) async throws -> Any {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        cfg.waitsForConnectivity = false
        let session = URLSession(configuration: cfg)
        let target = try url(path)
        // macOS Local Network privacy: the FIRST connection to a LAN host can fail with
        // -1009 (.notConnectedToInternet) / -1005 (.networkConnectionLost) while the OS
        // evaluates the permission. Retry once after a short delay before giving up.
        for attempt in 0..<2 {
            do {
                let (data, resp) = try await session.data(from: target)
                if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw ComfyError.http(http.statusCode)
                }
                guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw ComfyError.decode }
                return obj
            } catch let e as ComfyError {
                throw e
            } catch let e as URLError where attempt == 0 &&
                (e.code == .notConnectedToInternet || e.code == .networkConnectionLost) {
                try? await Task.sleep(nanoseconds: 800_000_000)
                continue
            } catch {
                throw ComfyError.unreachable(error.localizedDescription)
            }
        }
        throw ComfyError.unreachable("sem resposta")
    }

    func systemStats() async throws -> ComfyStats {
        guard let d = try await getJSON("/system_stats") as? [String: Any] else { throw ComfyError.decode }
        let sys = d["system"] as? [String: Any] ?? [:]
        let devs = (d["devices"] as? [[String: Any]]) ?? []
        let gpus = devs.enumerated().compactMap { (i, dev) -> ComfyGPU? in
            guard (dev["type"] as? String) == "cuda" || dev["vram_total"] != nil else { return nil }
            return ComfyGPU(index: dev["index"] as? Int ?? i,
                            name: (dev["name"] as? String) ?? "GPU \(i)",
                            vramTotal: int64(dev["vram_total"]),
                            vramFree: int64(dev["vram_free"]))
        }
        return ComfyStats(os: sys["os"] as? String ?? "?",
                          comfyVersion: sys["comfyui_version"] as? String ?? "?",
                          pythonVersion: shortPython(sys["python_version"] as? String ?? "?"),
                          pytorchVersion: sys["pytorch_version"] as? String ?? "?",
                          ramTotal: int64(sys["ram_total"]),
                          ramFree: int64(sys["ram_free"]),
                          gpus: gpus)
    }

    func models() async throws -> ComfyModels {
        guard let d = try await getJSON("/object_info") as? [String: Any] else { throw ComfyError.decode }
        func list(_ node: String) -> [String] {
            guard let n = d[node] as? [String: Any],
                  let req = (n["input"] as? [String: Any])?["required"] as? [String: Any] else { return [] }
            for (_, v) in req {
                if let arr = v as? [Any], let first = arr.first as? [Any] {
                    return first.compactMap { $0 as? String }
                }
            }
            return []
        }
        var m = ComfyModels()
        m.checkpoints = list("CheckpointLoaderSimple")
        m.unets = list("UNETLoader")
        m.loras = list("LoraLoader")
        m.vae = list("VAELoader")
        m.clip = list("CLIPLoader")
        m.controlnet = list("ControlNetLoader")
        return m
    }

    /// (running, pending) from /queue.
    func queueCounts() async throws -> (Int, Int) {
        guard let d = try await getJSON("/queue") as? [String: Any] else { throw ComfyError.decode }
        return ((d["queue_running"] as? [Any])?.count ?? 0, (d["queue_pending"] as? [Any])?.count ?? 0)
    }

    private func int64(_ any: Any?) -> Int64 {
        if let i = any as? Int64 { return i }
        if let i = any as? Int { return Int64(i) }
        if let d = any as? Double { return Int64(d) }
        if let n = any as? NSNumber { return n.int64Value }
        return 0
    }
    private func shortPython(_ s: String) -> String { String(s.prefix(while: { $0 != " " })) }
}

// MARK: - Capacity heuristic

/// Rough "will this model fit?" estimate. Filenames hint at precision: `fp8` ≈ 1 byte/param,
/// `bf16`/`fp16` ≈ 2 bytes/param. We can't read param counts from ComfyUI, so we estimate the
/// on-disk/VRAM weight tier from the name and compare against free VRAM with a working-set margin.
enum ComfyCapacity {
    /// Working-set headroom (latents, VAE decode, attention) on top of weights.
    static let headroomGB: Double = 3.0

    enum Fit { case fits, tight, tooBig, unknown }

    /// Estimate fit of a model file against the best single GPU's free VRAM.
    static func fit(filename: String, maxGPUFreeGB: Double) -> Fit {
        guard let weightGB = estimatedWeightGB(filename) else { return .unknown }
        let need = weightGB + headroomGB
        if need <= maxGPUFreeGB * 0.85 { return .fits }
        if need <= maxGPUFreeGB { return .tight }
        return .tooBig
    }

    /// Very rough weight-size estimate in GB from the filename's precision + size hints.
    static func estimatedWeightGB(_ name: String) -> Double? {
        let n = name.lowercased()
        // explicit param-size hints like "22b", "12b", "4b"
        var params: Double? = nil
        for token in n.replacingOccurrences(of: "-", with: " ").split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let t = String(token)
            if t.hasSuffix("b"), let v = Double(t.dropLast()), v > 0.5, v < 1000 { params = v }
        }
        let bytesPerParam: Double = n.contains("fp8") ? 1.0 : (n.contains("fp16") || n.contains("bf16") ? 2.0 : 2.0)
        if let p = params { return p * bytesPerParam }
        // No param hint: fall back to coarse family guesses.
        if n.contains("sd_xl") || n.contains("sdxl") { return 6.5 }      // SDXL base ~6.5GB fp16
        if n.contains("flux") { return n.contains("fp8") ? 11 : 22 }
        return nil
    }
}
