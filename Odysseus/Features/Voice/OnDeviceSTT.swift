import Foundation
import whisper

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

    var errorDescription: String? {
        switch self {
        case .cannotLoad(let name): return L("Não consegui carregar o modelo %@.", name)
        case .decodeFailed(let rc):  return L("Falha na transcrição: %@", "whisper.cpp rc=\(rc)")
        }
    }
}

/// One loaded on-device model. Loading is the expensive part (a Large-v3
/// turbo q5 takes seconds), so `VoiceInputManager` keeps the last engine
/// around and reuses it while the selected model does not change.
///
/// `transcribe` blocks for the whole decode and is not reentrant for the same
/// context, so callers run it off the main actor and one at a time.
protocol OnDeviceTranscriber: AnyObject {
    /// `samples` are mono 16 kHz PCM in [-1, 1]. `language` is a Whisper
    /// language code ("pt", "en", …) or "auto"; engines that auto-detect
    /// ignore it.
    func transcribe(_ samples: [Float], language: String) throws -> String
}

/// Thread count that leaves one core for the UI; whisper.cpp saturates what
/// it is given.
private var decodeThreads: Int32 {
    Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 1)))
}

final class WhisperEngine: OnDeviceTranscriber, @unchecked Sendable {
    private let ctx: OpaquePointer

    init(modelPath: String) throws {
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        // Flash attention on Metal is a pure win on Apple silicon; whisper.cpp
        // falls back silently where the backend lacks it.
        cparams.flash_attn = true
        guard let ctx = whisper_init_from_file_with_params(modelPath, cparams) else {
            throw OnDeviceSTTError.cannotLoad((modelPath as NSString).lastPathComponent)
        }
        self.ctx = ctx
    }

    deinit { whisper_free(ctx) }

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
        // The language pointer must outlive whisper_full, so the whole decode
        // sits inside withCString.
        let rc: Int32 = language.withCString { lang in
            params.language = lang
            params.detect_language = false
            return samples.withUnsafeBufferPointer { buf in
                whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
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
