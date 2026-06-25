import Foundation
@preconcurrency import AVFoundation
import Speech
import SwiftWhisper

/// Records the mic and transcribes to text using the engine chosen in Settings:
/// **native** (`SFSpeechRecognizer`) or **model** (a downloaded Whisper GGUF via
/// whisper.cpp).
///
/// Audio strategy: the tap copies *raw* mono samples at the hardware rate during
/// recording, then we resample the WHOLE recording to 16 kHz in a single pass at
/// stop. (Per-buffer resampling fragmented the converter's state and produced
/// garbage audio → Whisper guessed random languages and returned nothing.)
@MainActor
final class VoiceInputManager: ObservableObject {
    @Published var isRecording = false
    @Published var processing = false
    @Published var partialText = ""
    @Published var error: String?

    // A FRESH engine is created for every recording — reusing one instance across
    // start/stop is unstable on macOS (the 2nd use hung the audio HAL on the main
    // thread and then crashed). A new engine means a clean input node + tap.
    private var engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))

    private static let targetRate: Double = 16_000
    private static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                    sampleRate: targetRate, channels: 1, interleaved: false)!

    // Shared with the audio thread, guarded by `lock`.
    nonisolated(unsafe) private var rawSamples: [Float] = []
    nonisolated(unsafe) private var hwRate: Double = 48_000
    nonisolated(unsafe) private var captureToModel = false
    nonisolated(unsafe) private var request: SFSpeechAudioBufferRecognitionRequest?
    nonisolated(unsafe) private var sawFinal = false
    private let lock = NSLock()
    private var task: SFSpeechRecognitionTask?

    // Keep the loaded Whisper model in memory so repeated transcriptions don't
    // reload it from disk each time.
    private var cachedWhisper: Whisper?
    private var cachedModelID = ""

    private var useModel: Bool { UserDefaults.standard.string(forKey: "voice.stt.engine") == "model" }
    private var activeModelID: String { UserDefaults.standard.string(forKey: "voice.stt.model") ?? "" }

    // MARK: - Start

    func start() async -> Bool {
        #if targetEnvironment(simulator)
        error = "Microfone só funciona no iPhone (não no simulador)."
        return false
        #else
        // Re-entrancy guard: never start a second recording while one is active or
        // a transcription is still running (this was the 2nd-tap freeze/crash).
        guard !isRecording, !processing else { return false }
        error = nil; partialText = ""; sawFinal = false
        lock.withLock { rawSamples = [] }

        if useModel && installedModelURL() == nil {
            error = "Nenhum modelo Whisper baixado/selecionado. Baixe um em Ajustes › Voz e modelos (ou use o motor Nativo)."
            return false
        }
        guard await requestPermissions() else {
            error = "Permissão de microfone/voz negada (Ajustes do iPhone)."
            return false
        }
        // State may have changed while awaiting permission.
        guard !isRecording, !processing else { return false }
        // Tear down any leftover engine/tap and build a brand-new engine.
        tearDownEngine()
        engine = AVAudioEngine()

        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Áudio indisponível: \(error.localizedDescription)"
            return false
        }
        #endif

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            deactivateSession()
            self.error = "Microfone indisponível."
            return false
        }
        hwRate = inputFormat.sampleRate
        captureToModel = useModel

        if !useModel {
            guard let rec = recognizer, rec.isAvailable else {
                deactivateSession()
                error = "Reconhecimento de voz indisponível para pt-BR neste aparelho."
                return false
            }
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.requiresOnDeviceRecognition = rec.supportsOnDeviceRecognition
            request = req
            task = rec.recognitionTask(with: req) { [weak self] result, err in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.partialText = result.bestTranscription.formattedString
                        if result.isFinal { self.sawFinal = true }
                    }
                    if let err { self.error = "Reconhecimento: \(err.localizedDescription)"; self.sawFinal = true }
                }
            }
        }

        input.installTap(onBus: 0, bufferSize: 8192, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            if self.captureToModel { self.captureRaw(buffer) }
            else { self.request?.append(buffer) }
        }

        do {
            engine.prepare()
            try engine.start()
            isRecording = true
            return true
        } catch {
            input.removeTap(onBus: 0)
            deactivateSession()
            self.error = error.localizedDescription
            return false
        }
        #endif
    }

    // MARK: - Stop

    func stop() async -> String {
        guard isRecording else { return "" }
        isRecording = false
        tearDownEngine()
        request?.endAudio()
        deactivateSession()

        if useModel { return await transcribeWithWhisper() }

        for _ in 0..<30 { if sawFinal { break }; try? await Task.sleep(nanoseconds: 100_000_000) }
        task?.cancel(); task = nil; request = nil
        let text = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && error == nil { error = "Não captei nenhuma fala." }
        return text
    }

    func cancel() {
        guard isRecording else { return }
        isRecording = false
        tearDownEngine()
        task?.cancel(); task = nil; request = nil
        deactivateSession()
    }

    /// Stops the engine and removes its tap, tolerating a not-running engine.
    /// Removing the tap before deallocating the engine avoids dangling callbacks.
    private func tearDownEngine() {
        let e = engine
        e.inputNode.removeTap(onBus: 0)
        if e.isRunning { e.stop() }
    }

    /// Deactivates the audio session (iOS only — macOS has no AVAudioSession).
    private func deactivateSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Whisper

    private func transcribeWithWhisper() async -> String {
        guard let url = installedModelURL() else { error = "Nenhum modelo Whisper selecionado."; return "" }
        let raw = lock.withLock { rawSamples }
        guard raw.count > Int(hwRate * 0.3) else {   // < ~0.3 s
            error = "Áudio muito curto — toque, fale e toque de novo pra parar."
            return ""
        }
        processing = true; defer { processing = false }

        var frames = resampleTo16k(raw, from: hwRate)
        normalize(&frames)

        let lang: WhisperLanguage = (VoiceCatalog.all.first { $0.id == activeModelID }?.lang == .english)
            ? .english : .portuguese   // fixo: evita o "auto" chutar romeno em áudio imperfeito

        do {
            let whisper: Whisper
            if let cached = cachedWhisper, cachedModelID == activeModelID {
                whisper = cached                       // reuse — skips the disk reload
            } else {
                whisper = Whisper(fromFileURL: url)
                cachedWhisper = whisper
                cachedModelID = activeModelID
            }
            whisper.params.language = lang
            let segments = try await whisper.transcribe(audioFrames: frames)
            let text = segments.map(\.text).joined()
                .replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
                .replacingOccurrences(of: "[ Silence ]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { error = "Não captei nenhuma fala." }
            return text
        } catch {
            self.error = "Falha na transcrição: \(error.localizedDescription)"
            return ""
        }
    }

    private func installedModelURL() -> URL? {
        guard let model = VoiceCatalog.all.first(where: { $0.id == activeModelID }) else { return nil }
        let url = ModelDownloadManager.shared.localURL(model)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Audio plumbing

    /// Copies raw mono samples (hardware rate) — fast + safe inside the tap.
    nonisolated private func captureRaw(_ buffer: AVAudioPCMBuffer) {
        guard let chans = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        let chCount = Int(buffer.format.channelCount)
        var mono = [Float](repeating: 0, count: n)
        if chCount == 1 {
            _ = mono.withUnsafeMutableBufferPointer { memcpy($0.baseAddress!, chans[0], n * MemoryLayout<Float>.size) }
        } else {
            for i in 0..<n {
                var s: Float = 0
                for c in 0..<chCount { s += chans[c][i] }
                mono[i] = s / Float(chCount)
            }
        }
        lock.withLock { rawSamples.append(contentsOf: mono) }
    }

    /// One-pass resample of the whole recording → 16 kHz mono (continuous, so no
    /// fragmentation artifacts).
    private func resampleTo16k(_ samples: [Float], from rate: Double) -> [Float] {
        // Empty input → a 0-capacity PCM buffer has nil floatChannelData and the
        // [Float] has a nil baseAddress, so the memcpy unwraps below would crash.
        guard !samples.isEmpty, rate != Self.targetRate else { return samples }
        guard let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: inFormat, to: Self.targetFormat),
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return samples
        }
        inBuf.frameLength = AVAudioFrameCount(samples.count)
        _ = samples.withUnsafeBufferPointer { memcpy(inBuf.floatChannelData![0], $0.baseAddress!, samples.count * MemoryLayout<Float>.size) }

        let outCap = AVAudioFrameCount(Double(samples.count) * Self.targetRate / rate) + 4096
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: outCap) else { return samples }
        var done = false
        var err: NSError?
        conv.convert(to: outBuf, error: &err) { _, status in
            if done { status.pointee = .noDataNow; return nil }
            done = true; status.pointee = .haveData; return inBuf
        }
        guard let ch = outBuf.floatChannelData?[0] else { return samples }
        return Array(UnsafeBufferPointer(start: ch, count: Int(outBuf.frameLength)))
    }

    /// Peak-normalizes quiet recordings so Whisper has enough signal.
    private func normalize(_ x: inout [Float]) {
        var peak: Float = 0
        for v in x { peak = max(peak, abs(v)) }
        guard peak > 0.0001, peak < 0.97 else { return }
        let gain = 0.97 / peak
        for i in x.indices { x[i] *= gain }
    }

    private func requestPermissions() async -> Bool {
        let mic = await withCheckedContinuation { c in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        guard mic else { return false }
        if useModel { return true }
        let speech = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        return speech
    }
}
