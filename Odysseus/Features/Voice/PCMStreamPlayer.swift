import Foundation
@preconcurrency import AVFoundation

/// Plays mono Float32 audio that is still arriving.
///
/// `AVAudioPlayer` — what every other TTS path here uses — needs a complete
/// file before it can start, so a sentence costs a whole synthesis round trip
/// of silence before its first word. This plays what has arrived and keeps
/// appending, which is the only way the first word can start before the last
/// one exists.
///
/// It deliberately runs an **output-only** `AVAudioEngine` of its own rather
/// than borrowing the one `BargeInMonitor` owns. Hanging the player node on the
/// barge-in engine looks tempting — same VPIO unit, echo reference exactly
/// where the canceller wants it — but the device measurements already settle
/// the question: today's playback goes through `AVAudioPlayer`, which is also
/// outside that engine, and cancellation still drove the mic to `rms ≈ 0.000`
/// with residual at 0.006–0.022. So sharing buys nothing measurable and would
/// put a second owner inside the one component that was hardest to stabilise.
///
/// Engines are built per utterance. Reusing one across start/stop is unstable
/// on macOS — the same reason `VoiceInputManager` builds a fresh one per
/// recording.
@MainActor
final class PCMStreamPlayer {

    /// Fires once every scheduled buffer has actually been played back *and*
    /// the producer said no more are coming. Not called after `stop()`.
    var onFinished: (() -> Void)?
    /// Fires when the first buffer is handed to the node — not when the speaker
    /// actually moves. The engine is already running by then, so the gap is
    /// milliseconds, and the only thing riding on it is the UI's "preparing →
    /// speaking" swap. Barge-in is armed elsewhere, off the queue's own state.
    var onFirstAudio: (() -> Void)?

    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var format: AVAudioFormat?
    /// Buffers scheduled but not yet played to the end.
    private var outstanding = 0
    private var producerDone = false
    private var started = false
    /// Bumped by `stop()` so a completion callback from the previous utterance
    /// cannot finish the next one.
    private var epoch = 0
    private var firstAudioSent = false

    var isPlaying: Bool { started }

    /// Builds the graph for a stream of `sampleRate` mono audio and starts it.
    /// Called once the wire format is known — i.e. after the WAV header.
    func begin(sampleRate: Double) throws {
        stop()
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: sampleRate, channels: 1, interleaved: false)
        else { throw Failure.badFormat(sampleRate) }

        let e = AVAudioEngine()
        let n = AVAudioPlayerNode()
        e.attach(n)
        // Connect with the *source* format; the main mixer resamples to whatever
        // the hardware is running at.
        e.connect(n, to: e.mainMixerNode, format: fmt)
        e.prepare()
        try e.start()
        n.play()

        engine = e; node = n; format = fmt
        outstanding = 0; producerDone = false; started = true
        VoiceLog.log("tts.stream", "grafo pronto — \(Int(sampleRate)) Hz mono")
    }

    /// Queues more audio. Silently ignored before `begin` or after `stop`.
    func schedule(_ samples: [Float]) {
        guard started, let node, let format, !samples.isEmpty else { return }
        guard let buf = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(samples.count)),
              let dst = buf.floatChannelData?[0] else { return }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { dst.update(from: $0.baseAddress!, count: samples.count) }

        outstanding += 1
        let mine = epoch
        let first = outstanding == 1 && !firstAudioSent
        // `.dataPlayedBack` fires when the audio has actually left the node, not
        // when the node merely consumed the buffer — the difference is the tail
        // of the reply, and finishing the turn early would reopen the mic over
        // the assistant's own last word.
        node.scheduleBuffer(buf, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.drained(epoch: mine) }
        }
        if first {
            firstAudioSent = true
            onFirstAudio?()
        }
    }

    /// No more audio is coming. Finishes now if everything already drained.
    func endOfStream() {
        guard started else { return }
        producerDone = true
        finishIfDone()
    }

    /// Tears the graph down immediately — barge-in, engine switch, turn end.
    /// `onFinished` does **not** fire: a stop is not a completion, and treating
    /// it as one is what used to advance the queue on top of a live recording.
    func stop() {
        epoch &+= 1
        node?.stop()
        engine?.stop()
        node = nil; engine = nil; format = nil
        outstanding = 0; producerDone = false; started = false; firstAudioSent = false
    }

    private func drained(epoch e: Int) {
        guard e == epoch, started else { return }
        outstanding = max(0, outstanding - 1)
        finishIfDone()
    }

    private func finishIfDone() {
        guard started, producerDone, outstanding == 0 else { return }
        started = false
        node?.stop(); engine?.stop()
        node = nil; engine = nil; format = nil
        firstAudioSent = false
        onFinished?()
    }

    enum Failure: LocalizedError {
        case badFormat(Double)
        var errorDescription: String? {
            switch self {
            case .badFormat(let r): return "Taxa de amostragem inválida: \(Int(r)) Hz."
            }
        }
    }
}
