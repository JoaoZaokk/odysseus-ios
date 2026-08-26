import AVFoundation
import FluidAudio

/// Listens to the mic while the assistant speaks and fires `onSpeech` when the
/// user starts talking, letting the voice loop cut in (barge-in).
///
/// Detection is a neural voice-activity detector, not a loudness threshold.
/// Device traces showed why: echo cancellation works so well that the
/// assistant's own voice reads as ~0.000 RMS, which collapses any adaptive noise
/// floor to zero and leaves a fixed threshold deciding alone — and the residual
/// echo that leaks through (0.01–0.03 RMS) lands in the *same range* as the
/// user's actual speech. No amplitude threshold can separate those two, so this
/// asks a model whether the sound is a human voice instead of how loud it is.
///
/// Self-contained (its own engine) so it never disturbs the main STT/TTS path.
@MainActor
final class BargeInMonitor {
    private var engine = AVAudioEngine()
    private var running = false
    private var onSpeech: (() -> Void)?

    /// Shared across the app: the model is a few MB and loading it per turn
    /// would add a stall to every reply.
    private static var vad: VadManager?
    private static var vadLoadFailed = false

    // MARK: - Tuning

    /// Speech probability a chunk must reach. From the sensitivity slider:
    /// high sensitivity → lower bar → easier to interrupt.
    nonisolated(unsafe) private var speechThreshold: Float = 0.65
    /// Consecutive speech chunks required. Each chunk is 4096 samples at 16 kHz
    /// (256 ms), so two of them is roughly half a second of continuous voice —
    /// long enough to rule out a cough or a door.
    ///
    /// Three of them wherever the loudness floor cannot reject `loudestLeak` on
    /// its own — see `chunksForSensitivity`, which includes the default 0.5.
    ///
    /// Confirmed on device: with three required, the same class of spike that
    /// used to cut the assistant (0.046, 0.037, 0.031, all scoring 0.88–0.98 on
    /// the VAD) stalled at 1/3 and never fired, while a real interruption
    /// (0.141 then 0.081) reached 3/3 and cut immediately.
    nonisolated(unsafe) private var chunksNeeded = 2
    nonisolated(unsafe) private var speechChunks = 0

    /// Minimum level for a chunk to even reach the model.
    ///
    /// This is the second half of the decision, and it is not an optimization.
    /// The VAD answers "is this a human voice?", and echo residual *is* one —
    /// device traces show it scoring 1.00 at rms 0.014, which fired barge-in on
    /// the assistant's own words. What separates the two is loudness, and on
    /// device the gap is clean: residual sits at 0.006–0.022, the user's voice
    /// at 0.038–0.206. Requiring both keeps the model's judgement while ruling
    /// out anything too quiet to have come from the room.
    nonisolated(unsafe) private var speechFloor: Float = 0.04

    nonisolated static func floorForSensitivity(_ s: Double) -> Float {
        Float(0.055 - max(0, min(1, s)) * 0.027)   // s=0 → 0.055, s=1 → 0.028
    }

    nonisolated static func thresholdForSensitivity(_ s: Double) -> Float {
        Float(0.85 - max(0, min(1, s)) * 0.45)   // s=0 → 0.85 (hard), s=1 → 0.40 (easy)
    }

    /// Loudest echo excursion caught on device — a 0.046 spike, 2.4× the
    /// residual ceiling of the same session, which fired barge-in and cut the
    /// assistant mid-sentence onto eleven seconds of silence.
    ///
    /// It sits *above* the quietest voice ever measured (0.038), and that is
    /// the uncomfortable part: no floor can reject this leak while still
    /// accepting someone speaking softly. Loudness cannot separate them, so
    /// duration has to.
    static let loudestLeak: Float = 0.046

    /// Three chunks (768 ms) wherever the floor cannot reject that leak on its
    /// own, two (512 ms) where it can. Derived from the floor rather than
    /// written as its own sensitivity number, so the two cannot drift apart
    /// when the mapping is retuned.
    ///
    /// This crosses at a sensitivity of about 0.33, so the **default** 0.5 gets
    /// three — the first tuning here that changes behaviour at the default, and
    /// deliberately: the default's floor is 0.0415, under the leak, so what was
    /// validated at two chunks is exactly what produced the false cut.
    nonisolated static func chunksForSensitivity(_ s: Double) -> Int {
        floorForSensitivity(s) < loudestLeak ? 3 : 2
    }

    // MARK: - Resampling buffer
    //
    // The mic runs at the hardware rate (48 kHz on iPhone); the VAD model is
    // fixed at 16 kHz and 4096-sample chunks.

    private let bufLock = NSLock()
    nonisolated(unsafe) private var pending: [Float] = []
    /// Mean square of the *raw* samples behind each entry of `pending`, kept in
    /// step with it. The loudness gate has to be measured over the same span the
    /// model classifies: it used to read the RMS of the current 2048-sample tap
    /// buffer while judging a chunk assembled from roughly six of them, so one
    /// quiet trailing buffer could veto an otherwise clearly voiced chunk.
    /// Storing the raw energy (not the decimated one) keeps the floor in the
    /// units it was calibrated in on device.
    nonisolated(unsafe) private var pendingSq: [Float] = []
    nonisolated(unsafe) private var busy = false
    nonisolated(unsafe) private var decimation = 3

    /// Downloads and loads the VAD model. Call when the voice screen opens so the
    /// first reply isn't delayed by it.
    static func prepare() async {
        guard vad == nil, !vadLoadFailed else { return }
        do {
            vad = try await VadManager()
            VoiceLog.log("vad.load", "pronto")
        } catch {
            vadLoadFailed = true
            VoiceLog.log("vad.load", "FALHOU: \(error.localizedDescription) — barge-in ficará indisponível")
        }
    }

    /// Why the monitor refused to arm. These are refusals rather than degraded
    /// modes: without echo cancellation the monitor hears the assistant, and
    /// without the model it can only guess from loudness, which measurably does
    /// not work here.
    enum StartFailure {
        /// The model is still downloading/loading — the next sentence will arm
        /// normally, so the user is told nothing.
        case vadLoading
        case vadUnavailable
        case echoCancellation
        case microphone
        case simulator

        /// nil when there is nothing worth interrupting the user about.
        var message: String? {
            switch self {
            case .vadLoading, .simulator:
                return nil
            case .vadUnavailable:
                return L("Barge-in indisponível: o detector de voz não pôde ser carregado.")
            case .echoCancellation:
                return L("Barge-in indisponível: cancelamento de eco não pôde ser ativado.")
            case .microphone:
                return L("Barge-in indisponível: o microfone não pôde ser aberto.")
            }
        }
    }

    /// Returns nil once armed, or the reason it refused. The reason matters:
    /// every failure used to surface as "echo cancellation could not be
    /// enabled", which sent anyone troubleshooting a model that simply hadn't
    /// finished loading to look at AEC and microphone permissions instead.
    @discardableResult
    func start(onSpeech: @escaping () -> Void) -> StartFailure? {
        #if targetEnvironment(simulator)
        return .simulator   // no usable mic in the simulator
        #else
        guard Self.vad != nil else {
            let why: StartFailure = Self.vadLoadFailed ? .vadUnavailable : .vadLoading
            VoiceLog.log("barge.start", "sem modelo VAD (\(why)) — não armando")
            return why
        }
        // Re-arming (a new sentence) must not stack a second tap on the input
        // node, so an already-running monitor is torn down first.
        if running { stop() }
        self.onSpeech = onSpeech
        speechChunks = 0
        bufLock.lock(); pending.removeAll(); pendingSq.removeAll(); busy = false; bufLock.unlock()

        let s = UserDefaults.standard.object(forKey: "voice.bargein.sensitivity") as? Double ?? 0.5
        speechThreshold = Self.thresholdForSensitivity(s)
        speechFloor = Self.floorForSensitivity(s)
        chunksNeeded = Self.chunksForSensitivity(s)

        engine = AVAudioEngine()   // fresh engine each time (reuse is unstable)
        let input = engine.inputNode
        // Hard requirement, not best-effort: this is the only thing separating
        // the user's voice from the assistant's coming back through the speaker.
        do {
            try input.setVoiceProcessingEnabled(true)
            VoiceLog.log("barge.aec", "ativado")
        } catch {
            VoiceLog.log("barge.aec", "FALHOU: \(error.localizedDescription) — não armando")
            return .echoCancellation
        }
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            VoiceLog.log("barge.start", "formato inválido: \(format)")
            return .microphone
        }
        // Decimation can only go down. Below 16 kHz the rounded ratio collapses
        // to 0 (and then to 1 through max), which would hand the model
        // half-speed audio labelled as 16 kHz — worse than not arming.
        guard format.sampleRate >= 16_000 else {
            VoiceLog.log("barge.start", "taxa \(Int(format.sampleRate)) Hz < 16 kHz — não armando")
            return .microphone
        }
        decimation = max(1, Int((format.sampleRate / 16_000).rounded()))

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buf, _ in
            self?.analyze(buf)
        }
        engine.prepare()
        do { try engine.start(); running = true } catch {
            running = false
            VoiceLog.log("barge.start", "engine falhou: \(error.localizedDescription)")
        }
        VoiceLog.log("barge.start", "armado=\(running) rate=\(Int(format.sampleRate)) decim=\(decimation) limiar=\(speechThreshold) piso=\(speechFloor) blocos=\(chunksNeeded)")
        return running ? nil : .microphone
        #endif
    }

    func stop() {
        guard running else { return }
        VoiceLog.log("barge.stop")
        running = false
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        onSpeech = nil
        bufLock.lock(); pending.removeAll(); pendingSq.removeAll(); bufLock.unlock()
    }

    /// Averaging decimation, plus the mean square of the raw samples behind each
    /// output sample.
    ///
    /// Averaging rather than plain sample-dropping: dropping aliases, and
    /// aliasing looks like energy to the model. The raw energy is carried
    /// alongside so the loudness gate can be measured over exactly the span the
    /// model judges, instead of over whichever tap buffer happened to complete
    /// the chunk.
    ///
    /// Split out of `analyze` as a pure function so it can be tested without an
    /// audio device — the arithmetic is what the gate depends on.
    nonisolated static func decimate(_ s: UnsafeBufferPointer<Float>,
                                     by factor: Int) -> (down: [Float], meanSquares: [Float]) {
        guard factor > 0 else { return ([], []) }
        let n = s.count
        var down: [Float] = []
        var sqs: [Float] = []
        down.reserveCapacity(n / factor + 1)
        sqs.reserveCapacity(n / factor + 1)
        var i = 0
        while i + factor <= n {
            var acc: Float = 0
            var sq: Float = 0
            for k in 0..<factor { let v = s[i + k]; acc += v; sq += v * v }
            down.append(acc / Float(factor))
            sqs.append(sq / Float(factor))
            i += factor
        }
        return (down, sqs)
    }

    /// RMS of the raw audio behind a run of decimated samples, from the mean
    /// squares `decimate` produced. This is what the loudness gate reads.
    nonisolated static func rms(ofMeanSquares sqs: ArraySlice<Float>) -> Float {
        guard !sqs.isEmpty else { return 0 }
        return (sqs.reduce(0, +) / Float(sqs.count)).squareRoot()
    }

    /// Audio-thread callback: decimate to 16 kHz and hand full chunks to the
    /// model. Everything expensive happens off this thread.
    nonisolated private func analyze(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength); guard n > 0 else { return }

        let (down, downSq) = Self.decimate(UnsafeBufferPointer(start: ch, count: n), by: decimation)

        var chunk: [Float]?
        var rms: Float = 0
        bufLock.lock()
        pending.append(contentsOf: down)
        pendingSq.append(contentsOf: downSq)
        if !busy, pending.count >= VadManager.chunkSize {
            chunk = Array(pending.prefix(VadManager.chunkSize))
            pending.removeFirst(VadManager.chunkSize)
            rms = Self.rms(ofMeanSquares: pendingSq.prefix(VadManager.chunkSize))
            pendingSq.removeFirst(VadManager.chunkSize)
            busy = true
        }
        // A stalled model must not grow this without bound.
        if pending.count > VadManager.chunkSize * 8 {
            let drop = pending.count - VadManager.chunkSize * 4
            pending.removeFirst(drop)
            pendingSq.removeFirst(min(drop, pendingSq.count))
        }
        bufLock.unlock()

        guard let chunk else { return }

        // Too quiet, across the whole chunk, to be the user talking into the
        // phone. Skipping here also keeps the Neural Engine idle for most of a
        // reply. A miss costs one chunk off the run rather than the whole run:
        // zeroing it threw away a real interruption whenever one window of it
        // happened to fall quiet.
        guard rms > speechFloor else {
            bufLock.lock(); busy = false; bufLock.unlock()
            Task { @MainActor in self.speechChunks = max(0, self.speechChunks - 1) }
            VoiceLog.metered("barge.level", every: 1.0,
                             "\(VoiceLog.bar(rms)) rms=\(String(format: "%.4f", rms)) < piso \(String(format: "%.3f", speechFloor)) (VAD pulado)")
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await self.classify(chunk, rms: rms)
        }
    }

    nonisolated private func classify(_ chunk: [Float], rms: Float) async {
        defer { bufLock.lock(); busy = false; bufLock.unlock() }
        guard let vad = await Self.vad else { return }
        guard let results = try? await vad.process(chunk) else { return }
        let prob = results.map(\.probability).max() ?? 0

        await MainActor.run {
            let isSpeech = prob >= self.speechThreshold
            if isSpeech {
                self.speechChunks += 1
            } else {
                self.speechChunks = 0
            }
            VoiceLog.metered("barge.vad", every: 0.5,
                             "\(VoiceLog.bar(rms)) rms=\(String(format: "%.4f", rms)) fala=\(String(format: "%.2f", prob)) limiar=\(self.speechThreshold) blocos=\(self.speechChunks)/\(self.chunksNeeded)")
            if self.speechChunks >= self.chunksNeeded { self.fire() }
        }
    }

    @MainActor private func fire() {
        VoiceLog.log("barge.FIRE", "rodando=\(running) temCallback=\(onSpeech != nil)")
        guard running, let cb = onSpeech else { return }
        onSpeech = nil
        cb()
    }
}
