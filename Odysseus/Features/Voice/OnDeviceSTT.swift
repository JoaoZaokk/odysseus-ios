import Foundation
import whisper
#if os(iOS)
import UIKit
#endif

/// Which C engine inside the whisper.cpp xcframework decodes a model file.
///
/// Both ship in the same binary (`libwhisper` and `libparakeet` share one
/// ggml), so the catalog can mix them; only the loader differs. A model
/// declares its engine through its id prefix (`w-`/`u-` = Whisper, `p-` =
/// Parakeet) — see `VoiceModel.engine`.
enum STTModelEngine: String, Sendable {
    /// OpenAI Whisper family (ggml `.bin` from `convert-h5-to-ggml.py`).
    case whisper
    /// NVIDIA Parakeet TDT (ggml `.bin` from `convert-parakeet-to-ggml.py`).
    /// Auto-detects the language, so it ignores the language pin.
    case parakeet
}

enum OnDeviceSTTError: LocalizedError {
    case cannotLoad(String)
    case decodeFailed(Int32)
    case notEnoughMemory(needed: Int64, available: Int64)

    var errorDescription: String? {
        switch self {
        case .cannotLoad(let name): return L("Não consegui carregar o modelo %@.", name)
        case .decodeFailed(let rc):  return L("Falha na transcrição: %@", "whisper.cpp rc=\(rc)")
        case .notEnoughMemory(let needed, let available):
            return L("Este modelo não cabe na memória deste aparelho (precisa de %@, há %@ livres). Use um q5 ou o Parakeet.",
                     MemoryBudget.human(needed), MemoryBudget.human(available))
        }
    }
}

/// One loaded on-device model. Loading is the expensive part (a Large-v3
/// turbo q5 takes seconds; a Core ML encoder minutes on its first run), so
/// `STTRunner` keeps the last engine and reuses it while the model does not
/// change.
///
/// `transcribe` blocks for the whole decode and is not reentrant for the same
/// context: `STTRunner` serializes every call on its own queue.
protocol OnDeviceTranscriber: AnyObject {
    /// `samples` are mono 16 kHz PCM in [-1, 1]. `language` is a Whisper
    /// language code ("pt", "en", …) or "auto"; engines that auto-detect
    /// ignore it.
    func transcribe(_ samples: [Float], language: String) throws -> String
}

/// Thread count. whisper.cpp's own default is min(4, cores): on big.LITTLE
/// phones every extra thread lands on an efficiency core and, because ggml
/// joins all threads per op, drags each op down to that core's speed.
private var decodeThreads: Int32 {
    Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount)))
}

/// Routes whisper.cpp / ggml / parakeet log lines into the diagnostics store.
/// Without this every symptom looks like "slow" or "closed": the lines that
/// say `failed to load Core ML model`, `Core ML model loaded`, `compiled …
/// library in N sec` and `model size = … MB` only ever went to stderr.
private let installEngineLogSink: Void = {
    let sink: ggml_log_callback = { level, text, _ in
        guard let text else { return }
        let line = String(cString: text)
        DiagnosticsStore.shared.appendEngineLog(line)
        #if DEBUG
        if level == GGML_LOG_LEVEL_ERROR || level == GGML_LOG_LEVEL_WARN { VoiceLog.log("whisper", line) }
        #endif
    }
    ggml_log_set(sink, nil)
    whisper_log_set(sink, nil)
    parakeet_log_set(sink, nil)
}()

/// The Whisper language codes that get a style prompt. Advisory only: it nudges
/// the decoder to write numbers in words ("um centavo", not "1/100") and to
/// use the language's punctuation, it does not force anything.
enum STTPrompt {
    static func forLanguage(_ code: String) -> String? {
        if let custom = UserDefaults.standard.string(forKey: "voice.stt.prompt"), !custom.isEmpty { return custom }
        switch code {
        case "pt": return "Transcrição em português do Brasil. Números por extenso: um centavo, dois reais, vinte e cinco por cento, três e meio."
        case "en": return "Transcript in English. Numbers written out in words: one cent, two dollars, twenty-five percent, three and a half."
        case "es": return "Transcripción en español. Números en palabras: un centavo, dos euros, veinticinco por ciento."
        default:   return nil
        }
    }
}

final class WhisperEngine: OnDeviceTranscriber, @unchecked Sendable {
    private let ctx: OpaquePointer
    /// True when whisper.cpp found the Core ML encoder next to the model. The
    /// Core ML encoder has a fixed 30 s shape, so `audio_ctx` must stay at the
    /// default whenever it is in use.
    let usesCoreML: Bool

    init(modelPath: String) throws {
        _ = installEngineLogSink
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        // Flash attention on Metal is a pure win on Apple silicon; whisper.cpp
        // falls back silently where the backend lacks it.
        cparams.flash_attn = true
        guard let ctx = whisper_init_from_file_with_params(modelPath, cparams) else {
            throw OnDeviceSTTError.cannotLoad((modelPath as NSString).lastPathComponent)
        }
        self.ctx = ctx
        usesCoreML = FileManager.default.fileExists(atPath: Self.coreMLEncoderPath(forModelAt: modelPath))
    }

    deinit { whisper_free(ctx) }

    /// The path whisper.cpp itself derives for the Core ML encoder: drop the
    /// extension, drop a trailing `-qD_D` quantization suffix, add
    /// `-encoder.mlmodelc` (src/whisper.cpp, `whisper_get_coreml_path_encoder`).
    static func coreMLEncoderPath(forModelAt path: String) -> String {
        var p = path
        if let dot = p.lastIndex(of: "."), !p[dot...].contains("/") { p = String(p[..<dot]) }
        if let dash = p.lastIndex(of: "-") {
            let sub = p[dash...]
            if sub.count == 5, sub[sub.index(after: dash)] == "q", sub[sub.index(dash, offsetBy: 3)] == "_" {
                p = String(p[..<dash])
            }
        }
        return p + "-encoder.mlmodelc"
    }

    /// Encoder context for a clip: 320 samples per unit at 16 kHz, floored at
    /// whisper.cpp's own streaming default (768) so short dictations do not pay
    /// for a full 30 s window, capped at the model's 1500.
    static func audioContext(forSamples n: Int) -> Int32 {
        Int32(min(1500, max(768, n / 320 + 64)))
    }

    func transcribe(_ samples: [Float], language: String) throws -> String {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = decodeThreads
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.no_timestamps = true
        params.translate = false
        // Drop non-speech tokens so a quiet clip yields "" instead of
        // "[BLANK_AUDIO]"/"(music)" — the caller treats "" as "no speech".
        params.suppress_nst = true
        // The default fallback ladder (six temperatures × best_of 5) can run
        // 26 decoder passes on one noisy window and reallocates the KV cache.
        // Dictation wants one good pass and a cheap retry, not a search.
        params.temperature_inc = 0.4
        params.greedy.best_of = 2
        if !usesCoreML { params.audio_ctx = Self.audioContext(forSamples: samples.count) }
        let prompt = language == "auto" ? nil : STTPrompt.forLanguage(language)
        // Both pointers must outlive whisper_full, so the whole decode sits
        // inside the withCString scopes.
        let rc: Int32 = language.withCString { lang in
            params.language = lang
            params.detect_language = false
            func run() -> Int32 {
                samples.withUnsafeBufferPointer { buf in
                    whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
                }
            }
            if let prompt {
                return prompt.withCString { p in params.initial_prompt = p; return run() }
            }
            return run()
        }
        guard rc == 0 else { throw OnDeviceSTTError.decodeFailed(rc) }
        var text = ""
        for i in 0..<whisper_full_n_segments(ctx) {
            if let seg = whisper_full_get_segment_text(ctx, i) { text += String(cString: seg) }
        }
        return text
    }
}

final class ParakeetEngine: OnDeviceTranscriber, @unchecked Sendable {
    private let ctx: OpaquePointer

    init(modelPath: String) throws {
        _ = installEngineLogSink
        var cparams = parakeet_context_default_params()
        cparams.use_gpu = true
        guard let ctx = parakeet_init_from_file_with_params(modelPath, cparams) else {
            throw OnDeviceSTTError.cannotLoad((modelPath as NSString).lastPathComponent)
        }
        self.ctx = ctx
    }

    deinit { parakeet_free(ctx) }

    func transcribe(_ samples: [Float], language: String) throws -> String {
        var params = parakeet_full_default_params(PARAKEET_SAMPLING_GREEDY)
        params.n_threads = decodeThreads
        let rc = samples.withUnsafeBufferPointer { buf in
            parakeet_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }
        guard rc == 0 else { throw OnDeviceSTTError.decodeFailed(rc) }
        var text = ""
        for i in 0..<parakeet_full_n_segments(ctx) {
            if let seg = parakeet_full_get_segment_text(ctx, i) { text += String(cString: seg) }
        }
        return text
    }
}

enum OnDeviceSTT {
    /// Loads the right engine for a catalog model.
    static func load(_ model: VoiceModel, at url: URL) throws -> OnDeviceTranscriber {
        switch model.engine {
        case .whisper:  return try WhisperEngine(modelPath: url.path)
        case .parakeet: return try ParakeetEngine(modelPath: url.path)
        }
    }
}

/// The single owner of the loaded model, process-wide.
///
/// Three `VoiceInputManager`s exist at once (chat composer, voice sheet, the
/// test bench in Settings) and each used to cache its own context — two
/// copies of a 1.6 GB turbo in one process, which is past the jetsam line on
/// an 8 GB phone. Now there is one context, loaded and decoded on a serial
/// queue (never the main actor: the load alone froze the UI for the whole
/// read of the file plus the Metal library compile), released on a memory
/// warning, in the background, and when its model is deleted. Every risky
/// step opens a span in `DiagnosticsStore` first, so a silent death leaves a
/// `death.suspected` breadcrumb with the model id and the memory that was
/// left.
final class STTRunner: @unchecked Sendable {
    static let shared = STTRunner()

    private let queue = DispatchQueue(label: "com.zao.odysseus.stt", qos: .userInitiated)
    private var engine: OnDeviceTranscriber?
    private var engineID = ""
    private var observers: [NSObjectProtocol] = []

    private init() {
        #if os(iOS)
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in
            self?.release(reason: "memory_warning")
        })
        observers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.release(reason: "background")
        })
        #endif
    }

    /// Rough resident cost of a model: ggml weights are read whole (no mmap)
    /// plus compute buffers and KV caches; the Core ML encoder adds its own
    /// weights on top (whisper.cpp keeps the ggml encoder too).
    static func memoryRequired(for model: VoiceModel, coreMLBytes: Int64) -> Int64 {
        Int64(Double(model.bytes) * 1.3) + coreMLBytes + 300_000_000
    }

    /// nil = unknown (macOS), otherwise whether the model fits under the jetsam
    /// line right now.
    static func fits(_ model: VoiceModel, coreMLBytes: Int64) -> Bool? {
        guard let avail = MemoryBudget.availableBytes else { return nil }
        return memoryRequired(for: model, coreMLBytes: coreMLBytes) <= avail
    }

    var loadedModelID: String { queue.sync { engineID } }

    func release(reason: String) {
        queue.async { [self] in
            guard engine != nil else { return }
            DiagnosticsStore.shared.event("stt.release", ["model": engineID, "reason": reason])
            engine = nil; engineID = ""
        }
    }

    func releaseIfLoaded(id: String) {
        queue.async { [self] in
            guard engineID == id else { return }
            DiagnosticsStore.shared.event("stt.release", ["model": id, "reason": "deleted"])
            engine = nil; engineID = ""
        }
    }

    /// Loads (if needed) and decodes, off the main actor. `onLoading` fires on
    /// the queue right before a load starts, so the UI can say "loading…".
    func transcribe(model: VoiceModel, url: URL, coreMLBytes: Int64, samples: [Float], language: String,
                    onLoading: (@Sendable () -> Void)? = nil) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                do {
                    let diag = DiagnosticsStore.shared
                    if engine == nil || engineID != model.id {
                        if engine != nil {
                            diag.event("stt.evict", ["model": engineID, "availMB": MemoryBudget.mb(MemoryBudget.availableBytes)])
                            engine = nil; engineID = ""
                        }
                        let need = Self.memoryRequired(for: model, coreMLBytes: coreMLBytes)
                        if let avail = MemoryBudget.availableBytes, need > avail {
                            diag.event("stt.load.refused", ["model": model.id, "needMB": MemoryBudget.mb(need), "availMB": MemoryBudget.mb(avail)])
                            throw OnDeviceSTTError.notEnoughMemory(needed: need, available: avail)
                        }
                        onLoading?()
                        diag.beginSpan("stt.load", ["model": model.id, "engine": model.engine.rawValue,
                                                    "bytes": String(model.bytes), "coremlMB": MemoryBudget.mb(coreMLBytes),
                                                    "availMB": MemoryBudget.mb(MemoryBudget.availableBytes),
                                                    "physMB": MemoryBudget.mb(MemoryBudget.physicalBytes),
                                                    "threads": String(decodeThreads)])
                        do {
                            engine = try OnDeviceSTT.load(model, at: url)
                            engineID = model.id
                        } catch {
                            diag.failSpan("stt.load", error.localizedDescription)
                            throw error
                        }
                        diag.endSpan("stt.load", ["availMB": MemoryBudget.mb(MemoryBudget.availableBytes),
                                                  "coreml": (engine as? WhisperEngine)?.usesCoreML == true ? "1" : "0"])
                    }
                    guard let engine else { throw OnDeviceSTTError.cannotLoad(model.name) }
                    diag.beginSpan("stt.decode", ["model": model.id, "samples": String(samples.count),
                                                  "seconds": String(format: "%.1f", Double(samples.count) / 16_000),
                                                  "lang": language])
                    do {
                        let text = try engine.transcribe(samples, language: language)
                        diag.endSpan("stt.decode", ["chars": String(text.count)])
                        cont.resume(returning: text)
                    } catch {
                        diag.failSpan("stt.decode", error.localizedDescription)
                        throw error
                    }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
