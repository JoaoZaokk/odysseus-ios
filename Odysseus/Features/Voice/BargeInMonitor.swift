import AVFoundation

/// Listens to the mic **while the assistant is speaking** and fires `onSpeech`
/// when the user starts talking — letting the voice loop cut the reply short
/// (barge-in). Voice-processing (acoustic echo cancellation) is enabled so the
/// assistant's own audio coming out of the speaker is largely removed from the
/// mic and doesn't trip a false interruption.
///
/// Self-contained (its own engine) so it never disturbs the main STT/TTS path.
@MainActor
final class BargeInMonitor {
    private var engine = AVAudioEngine()
    private var running = false
    private var onSpeech: (() -> Void)?

    /// RMS above `threshold` = sound; `hotNeeded` consecutive hot buffers = real
    /// speech (not a transient). `threshold` comes from the user's sensitivity
    /// setting (higher sensitivity → lower threshold → easier to interrupt).
    nonisolated(unsafe) private var threshold: Float = 0.07
    private let hotNeeded = 4
    nonisolated(unsafe) private var hotCount = 0

    static func thresholdForSensitivity(_ s: Double) -> Float {
        Float(0.13 - max(0, min(1, s)) * 0.11)   // s=0 → 0.13 (hard), s=1 → 0.02 (easy)
    }

    func start(onSpeech: @escaping () -> Void) {
        #if targetEnvironment(simulator)
        return   // no usable mic in the simulator
        #else
        guard !running else { return }
        self.onSpeech = onSpeech
        hotCount = 0
        let s = UserDefaults.standard.object(forKey: "voice.bargein.sensitivity") as? Double ?? 0.5
        threshold = Self.thresholdForSensitivity(s)
        engine = AVAudioEngine()   // fresh engine each time (reuse is unstable)
        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(true)   // AEC against the speaker output
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buf, _ in
            self?.analyze(buf)
        }
        engine.prepare()
        do { try engine.start(); running = true } catch { running = false }
        #endif
    }

    func stop() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        onSpeech = nil
    }

    nonisolated private func analyze(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength); guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { let s = ch[i]; sum += s * s }
        let rms = (sum / Float(n)).squareRoot()
        if rms > threshold {
            hotCount += 1
            if hotCount >= hotNeeded { Task { @MainActor in self.fire() } }
        } else {
            hotCount = max(0, hotCount - 1)
        }
    }

    @MainActor private func fire() {
        guard running, let cb = onSpeech else { return }
        onSpeech = nil
        cb()
    }
}
