import XCTest
@testable import Odysseus

/// Regression tests for the voice pipeline's pure arithmetic and text handling.
///
/// Scope note: this covers the parts that are decidable without hardware. The
/// barge-in *decision* also depends on a neural VAD and on real echo-cancelled
/// microphone audio, neither of which exists in a unit test or in the
/// simulator — that half still needs recorded device audio, and these tests do
/// not pretend to cover it. What they do cover is the arithmetic that a wrong
/// answer there would be blamed on.
final class VoicePipelineTests: XCTestCase {

    // MARK: - Decimation and the loudness window

    private func decimate(_ a: [Float], by f: Int) -> (down: [Float], meanSquares: [Float]) {
        a.withUnsafeBufferPointer { BargeInMonitor.decimate($0, by: f) }
    }

    func testDecimationAveragesEachGroup() {
        let (down, _) = decimate([0, 3, 6, 1, 1, 1], by: 3)
        XCTAssertEqual(down, [3, 1])
    }

    func testDecimationDropsTheIncompleteTailGroup() {
        // 7 samples at factor 3 yields 2 outputs; the leftover sample is not
        // averaged against zeros, which would fabricate a quiet sample.
        let (down, sq) = decimate(Array(repeating: 1, count: 7), by: 3)
        XCTAssertEqual(down.count, 2)
        XCTAssertEqual(sq.count, 2)
    }

    func testDecimationFactorOneIsIdentity() {
        let input: [Float] = [-0.5, 0.25, 1]
        let (down, _) = decimate(input, by: 1)
        XCTAssertEqual(down, input)
    }

    /// The heart of the fix: the level gate must describe the same audio the
    /// model classifies. It used to read the RMS of whichever 2048-sample tap
    /// buffer happened to complete the chunk, so one quiet trailing buffer
    /// could veto an otherwise clearly voiced 256 ms window.
    func testChunkRMSMatchesTheRawAudioBehindThatChunk() {
        let factor = 3
        let chunkLen = 64                       // stands in for VadManager.chunkSize
        // Deterministic, and deliberately uneven: loud at the front, near
        // silence at the back, which is exactly the shape that used to defeat
        // the gate.
        let raw: [Float] = (0..<(chunkLen * factor)).map { i in
            i < chunkLen * factor / 2 ? 0.2 : 0.002
        }
        let (_, sq) = decimate(raw, by: factor)

        let reported = BargeInMonitor.rms(ofMeanSquares: sq.prefix(chunkLen))
        let direct = (raw.reduce(0) { $0 + $1 * $1 } / Float(raw.count)).squareRoot()

        XCTAssertEqual(reported, direct, accuracy: 1e-6,
                       "the gate must measure the whole chunk, not one buffer of it")
    }

    func testChunkRMSIgnoresAudioBeyondTheChunk() {
        let factor = 2
        let chunkLen = 32
        // A loud chunk followed by silence that belongs to the *next* chunk.
        let loud = [Float](repeating: 0.3, count: chunkLen * factor)
        let quiet = [Float](repeating: 0, count: chunkLen * factor)
        let (_, sq) = decimate(loud + quiet, by: factor)

        let first = BargeInMonitor.rms(ofMeanSquares: sq.prefix(chunkLen))
        XCTAssertEqual(first, 0.3, accuracy: 1e-6)

        let second = BargeInMonitor.rms(ofMeanSquares: sq.dropFirst(chunkLen).prefix(chunkLen))
        XCTAssertEqual(second, 0, accuracy: 1e-6)
    }

    func testRMSOfNothingIsZeroRatherThanNaN() {
        XCTAssertEqual(BargeInMonitor.rms(ofMeanSquares: ArraySlice<Float>()), 0)
    }

    // MARK: - Sensitivity mapping

    func testSensitivityMovesBothGatesTowardEasierInterruption() {
        // Higher sensitivity must lower both bars, or the slider fights itself.
        XCTAssertGreaterThan(BargeInMonitor.thresholdForSensitivity(0),
                             BargeInMonitor.thresholdForSensitivity(1))
        XCTAssertGreaterThan(BargeInMonitor.floorForSensitivity(0),
                             BargeInMonitor.floorForSensitivity(1))
    }

    func testSensitivityIsClampedOutsideZeroToOne() {
        XCTAssertEqual(BargeInMonitor.thresholdForSensitivity(-5),
                       BargeInMonitor.thresholdForSensitivity(0))
        XCTAssertEqual(BargeInMonitor.floorForSensitivity(9),
                       BargeInMonitor.floorForSensitivity(1))
    }

    /// The floor separates echo residual from the user's voice, using numbers
    /// measured on device: residual 0.006–0.022, user 0.038–0.206.
    ///
    /// It must clear the residual at *every* slider position — admitting echo is
    /// the failure that made barge-in interrupt the assistant's own words. It
    /// deliberately does **not** stay under 0.038 across the range: at low
    /// sensitivity the floor sits above a quiet voice on purpose, which is what
    /// "low sensitivity means you have to speak up" means. Only the top of the
    /// slider needs to reach a soft speaker.
    func testFloorAlwaysClearsEchoResidual() {
        for s in stride(from: 0.0, through: 1.0, by: 0.1) {
            XCTAssertGreaterThan(BargeInMonitor.floorForSensitivity(s), 0.022,
                                 "floor would admit echo residual at s=\(s)")
        }
    }

    func testMaximumSensitivityReachesASoftVoice() {
        XCTAssertLessThan(BargeInMonitor.floorForSensitivity(1), 0.038)
    }

    // MARK: - Sentence cutting (time-to-first-word)

    func testCutsOnATerminatorFollowedByWhitespace() {
        let s = "Oi. Tudo bem?"
        XCTAssertEqual(VoiceConversation.sentenceCut(in: s), 3)
    }

    func testDecimalNumbersAreNotSentenceBreaks() {
        XCTAssertNil(VoiceConversation.sentenceCut(in: "A versão 3.5 saiu"))
    }

    func testThousandsSeparatorsAreNotSentenceBreaks() {
        XCTAssertNil(VoiceConversation.sentenceCut(in: "Custa R$ 1.200,00 hoje"))
    }

    func testNewlineEndsASentence() {
        XCTAssertEqual(VoiceConversation.sentenceCut(in: "Primeira\nSegunda"), 9)
    }

    func testCJKTerminatorsCut() {
        XCTAssertNotNil(VoiceConversation.sentenceCut(in: "こんにちは。 元気ですか"))
    }

    func testNoCutWhileTheSentenceIsStillArriving() {
        XCTAssertNil(VoiceConversation.sentenceCut(in: "ainda escrevendo"))
        // A terminator at the very end has no following whitespace yet — the
        // next delta may turn it into "3.5". Waiting is correct.
        XCTAssertNil(VoiceConversation.sentenceCut(in: "quase pronto."))
    }

    // MARK: - Speakability

    func testMarkdownOnlyTextIsNotSpeakable() {
        // Committing the loop to .speaking for one of these left the turn with
        // an empty queue that could never be closed.
        for junk in ["```", "**", "---", "   ", "#"] {
            XCTAssertFalse(SpeechManager.isSpeakable(junk), "\(junk) should not be spoken")
        }
    }

    func testOrdinaryTextIsSpeakable() {
        XCTAssertTrue(SpeechManager.isSpeakable("Bom dia"))
        XCTAssertTrue(SpeechManager.isSpeakable("**negrito** conta"))
    }

    // MARK: - Transcription language

    func testISO639DropsRegionAndScriptSubtags() {
        XCTAssertEqual(AppLanguage.ptBR.iso639, "pt")
        XCTAssertEqual(AppLanguage.zhHans.iso639, "zh")
        XCTAssertEqual(AppLanguage.zhHant.iso639, "zh")
        XCTAssertEqual(AppLanguage.deAT.iso639, "de")
    }

    func testISO639LeavesBareCodesAlone() {
        XCTAssertEqual(AppLanguage.en.iso639, "en")
        XCTAssertEqual(AppLanguage.ja.iso639, "ja")
    }

    func testEveryLanguageProducesATwoLetterCode() {
        // Transcription APIs take ISO-639-1; a longer or empty code would be
        // rejected or silently ignored.
        for lang in AppLanguage.allCases {
            XCTAssertEqual(lang.iso639.count, 2, "\(lang.rawValue) → \(lang.iso639)")
        }
    }

    // MARK: - Speech language setting

    @MainActor
    private func withSpeechLanguage(_ raw: String?, _ body: () -> Void) {
        let d = UserDefaults.standard
        let saved = d.string(forKey: SpeechLanguage.key)
        defer {
            if let saved { d.set(saved, forKey: SpeechLanguage.key) }
            else { d.removeObject(forKey: SpeechLanguage.key) }
        }
        if let raw { d.set(raw, forKey: SpeechLanguage.key) }
        else { d.removeObject(forKey: SpeechLanguage.key) }
        body()
    }

    @MainActor func testUnsetSpeechLanguageFollowsTheApp() {
        withSpeechLanguage(nil) {
            XCTAssertEqual(SpeechLanguage.pinned(), LocalizationManager.shared.active)
        }
    }

    @MainActor func testExplicitSpeechLanguageWinsOverTheApp() {
        // The whole point of the setting: dictate Japanese without moving the
        // entire UI to Japanese.
        withSpeechLanguage(AppLanguage.ja.rawValue) {
            XCTAssertEqual(SpeechLanguage.pinned(), .ja)
        }
    }

    @MainActor func testDetectPinsNothing() {
        withSpeechLanguage(SpeechLanguage.auto) {
            XCTAssertNil(SpeechLanguage.pinned())
        }
    }

    @MainActor func testUnknownStoredCodeFallsBackToTheAppNotToDetection() {
        // A code dropped by a later build must not quietly become auto-detect,
        // which is the worse of the two failures on short or noisy audio.
        withSpeechLanguage("xx-YY") {
            XCTAssertEqual(SpeechLanguage.pinned(), LocalizationManager.shared.active)
        }
    }

    // MARK: - Opening cut (first chunk of a reply)

    func testOpeningPrefersARealSentenceWhenThereIsOne() {
        let s = "Oi. " + String(repeating: "a", count: 200)
        XCTAssertEqual(VoiceConversation.openingCut(in: s), 3)
    }

    func testOpeningLeavesAShortReplyAlone() {
        // Under the soft floor and no terminator yet: waiting is right, the
        // looser rule exists to shorten silence, not to chop three words out.
        XCTAssertNil(VoiceConversation.openingCut(in: "Deixa eu ver isso pra você"))
    }

    func testOpeningCutsAtTheLastClauseBreakInBudget() {
        let head = String(repeating: "a", count: 55)   // first comma lands under the floor
        let mid = String(repeating: "b", count: 30)
        let s = head + ", " + mid + ", " + String(repeating: "c", count: 200)
        XCTAssertEqual(VoiceConversation.openingCut(in: s), head.count + 2 + mid.count + 1)
    }

    func testOpeningNeverCutsBeforeTheSoftFloor() {
        let s = "Sim, " + Array(repeating: "palavra", count: 60).joined(separator: " ")
        let cut = try! XCTUnwrap(VoiceConversation.openingCut(in: s))
        XCTAssertGreaterThanOrEqual(cut, VoiceConversation.openingSoft)
        XCTAssertLessThanOrEqual(cut, VoiceConversation.openingHard)
    }

    func testOpeningFallbackDoesNotSplitAWord() {
        let s = Array(repeating: "palavra", count: 60).joined(separator: " ")
        let chars = Array(s)
        let cut = try! XCTUnwrap(VoiceConversation.openingCut(in: s))
        XCTAssertTrue(chars[cut].isWhitespace)
        XCTAssertFalse(chars[cut - 1].isWhitespace)
    }

    func testOpeningStillDoesNotBreakADecimal() {
        // Past the soft floor, no clause break, short of the hard limit: the
        // looser rule must not invent a cut at "3.5".
        XCTAssertNil(VoiceConversation.openingCut(in:
            "A versão 3.5 saiu ontem e mudou bastante coisa no modelo"))
    }

    // MARK: - Streamed WAV decoding

    private func u16le(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    private func u32le(_ v: Int) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    private func wav(rate: Int = 44_100, channels: Int = 1, bits: Int = 16, tag: Int = 1,
                     junkChunk: Bool = false, declaredDataSize: Int? = nil,
                     payload: [UInt8]) -> Data {
        var d = [UInt8]("RIFF".utf8)
        d += u32le(0xFFFF_FFF0)            // servers streaming a WAV cannot know this
        d += [UInt8]("WAVE".utf8)
        if junkChunk {
            d += [UInt8]("LIST".utf8) + u32le(4) + [UInt8]("INFO".utf8)
        }
        d += [UInt8]("fmt ".utf8) + u32le(16)
        d += u16le(tag) + u16le(channels) + u32le(rate)
        d += u32le(rate * channels * bits / 8) + u16le(channels * bits / 8) + u16le(bits)
        d += [UInt8]("data".utf8) + u32le(declaredDataSize ?? payload.count) + payload
        return Data(d)
    }

    func testWAVHeaderIsRead() throws {
        var dec = WAVStreamDecoder()
        _ = try dec.append(wav(payload: [1, 0, 2, 0]))
        XCTAssertEqual(dec.format, .init(sampleRate: 44_100, channels: 1,
                                         bitsPerSample: 16, isFloat: false))
    }

    func testChunksBeforeFmtAreSkipped() throws {
        var dec = WAVStreamDecoder()
        _ = try dec.append(wav(rate: 24_000, junkChunk: true, payload: [1, 0]))
        XCTAssertEqual(dec.format?.sampleRate, 24_000)
    }

    func testDeclaredSizesAreIgnored() throws {
        // A streamed WAV commonly declares 0 or 0xFFFFFFFF for the data chunk;
        // trusting it would truncate or overrun the reply.
        var dec = WAVStreamDecoder()
        let out = try dec.append(wav(declaredDataSize: 0, payload: [1, 0, 2, 0, 3, 0]))
        XCTAssertEqual(out.count, 6)
    }

    func testABogusNonDataChunkSizeIsRejectedRatherThanWaitedOn() {
        // The reason the `data` size is ignored applies to every other chunk
        // too: a server streaming a WAV it has not finished writing declares
        // whatever it likes. Waiting for a LIST chunk that claims 4 GB grew
        // `pending` for the whole response and then reported "no audio" for a
        // perfectly good WAV, so an implausible header chunk must be an error.
        var dec = WAVStreamDecoder()
        var d = [UInt8]("RIFF".utf8) + u32le(0xFFFF_FFF0) + [UInt8]("WAVE".utf8)
        d += [UInt8]("LIST".utf8) + u32le(0xFFFF_FFFF) + [UInt8]("INFO".utf8)
        XCTAssertThrowsError(try dec.append(Data(d)))
    }

    func testAnHonestNonDataChunkIsStillSkipped() throws {
        // The cap must not break the ordinary case it is guarding.
        var dec = WAVStreamDecoder()
        let out = try dec.append(wav(junkChunk: true, payload: [1, 0, 2, 0]))
        XCTAssertEqual(out.count, 4)
    }

    func testBytesSplitAcrossArrivalsReassemble() throws {
        let payload = (0..<200).map { UInt8($0 % 251) }
        let whole = wav(payload: payload)
        var dec = WAVStreamDecoder()
        var got = Data()
        // Deliberately awkward slices: a header cut in half, then odd sizes that
        // straddle frame boundaries.
        var i = 0
        for size in [7, 13, 1, 40, 3, 9999] {
            guard i < whole.count else { break }
            let end = min(i + size, whole.count)
            got += try dec.append(whole.subdata(in: i..<end))
            i = end
        }
        XCTAssertEqual([UInt8](got), payload)
    }

    func testPartialFrameIsHeldBack() throws {
        var dec = WAVStreamDecoder()
        let header = wav(payload: [])
        _ = try dec.append(header)
        XCTAssertEqual(try dec.append(Data([0x11])).count, 0, "half a 16-bit frame is not playable")
        XCTAssertEqual([UInt8](try dec.append(Data([0x22]))), [0x11, 0x22])
    }

    func testNonRIFFIsRejected() {
        var dec = WAVStreamDecoder()
        XCTAssertThrowsError(try dec.append(Data("{\"error\":\"nope\"}xxxx".utf8))) { e in
            XCTAssertEqual(e as? WAVStreamDecoder.Failure, .notRIFF)
        }
    }

    func testUnsupportedCodecIsRejectedRatherThanPlayedAsNoise() {
        var dec = WAVStreamDecoder()
        // tag 2 is ADPCM: decoding it as linear PCM produces full-volume noise.
        XCTAssertThrowsError(try dec.append(wav(tag: 2, payload: [1, 0])))
    }

    func testInt16ConvertsToMinusOneToOne() {
        let f = WAVStreamDecoder.Format(sampleRate: 16_000, channels: 1,
                                        bitsPerSample: 16, isFloat: false)
        let out = WAVStreamDecoder.monoFloat(Data([0x00, 0x00, 0x00, 0x80, 0xFF, 0x7F]), f)
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out[0], 0, accuracy: 1e-6)
        XCTAssertEqual(out[1], -1, accuracy: 1e-6)
        XCTAssertEqual(out[2], 1, accuracy: 1e-4)
    }

    func testStereoIsDownmixed() {
        let f = WAVStreamDecoder.Format(sampleRate: 16_000, channels: 2,
                                        bitsPerSample: 16, isFloat: false)
        // L = +1.0 (0x7FFF), R = -1.0 (0x8000) → silence, not two samples.
        let out = WAVStreamDecoder.monoFloat(Data([0xFF, 0x7F, 0x00, 0x80]), f)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0], 0, accuracy: 1e-4)
    }

    func testFloat32PassesThrough() {
        let f = WAVStreamDecoder.Format(sampleRate: 44_100, channels: 1,
                                        bitsPerSample: 32, isFloat: true)
        var bytes = [UInt8]()
        for v in [Float(0.25), Float(-0.5)] {
            let b = v.bitPattern
            bytes += [UInt8(b & 0xFF), UInt8((b >> 8) & 0xFF),
                      UInt8((b >> 16) & 0xFF), UInt8((b >> 24) & 0xFF)]
        }
        let out = WAVStreamDecoder.monoFloat(Data(bytes), f)
        XCTAssertEqual(out, [0.25, -0.5])
    }

    // MARK: - How long a run has to be

    func testEverythingAboveMinimumDemandsTheLongerRun() {
        // The floor is under the observed leak everywhere except the very
        // bottom, so two chunks were never going to reject it — this is the
        // case that actually broke.
        XCTAssertEqual(BargeInMonitor.chunksForSensitivity(0.2), 3)
        XCTAssertEqual(BargeInMonitor.chunksForSensitivity(0.5), 3)
        XCTAssertEqual(BargeInMonitor.chunksForSensitivity(1), 3)
    }

    func testMinimumSensitivityKeepsTheShorterRun() {
        // Only at the bottom does the floor alone reject the leak, and there is
        // nothing to buy by also making the user hold a syllable longer.
        XCTAssertEqual(BargeInMonitor.chunksForSensitivity(0), 2)
    }

    func testTheDefaultAdmitsTheQuietestVoiceEverMeasured() {
        // The reason the mapping was retuned in build 16. The old default floor
        // was 0.0415, above the 0.038 of the quietest voice in the device
        // traces, so a soft-spoken user could not interrupt at the setting the
        // app actually ships with — and that setting had never been exercised
        // on a device, because every barge-in run was done at maximum.
        XCTAssertLessThan(BargeInMonitor.floorForSensitivity(0.5), 0.038)
    }

    func testNoSettingLetsTheResidualCeilingThroughToTheModel() {
        // The other side of the same trade: drop the floor far enough and the
        // 0.006–0.022 residual reaches the VAD, which scores it 1.00.
        for i in 0...100 {
            XCTAssertGreaterThan(BargeInMonitor.floorForSensitivity(Double(i) / 100), 0.022,
                                 "s=\(Double(i) / 100)")
        }
    }

    func testTheLongerRunStartsExactlyWhereTheFloorStopsRejectingTheLeak() {
        for i in 0...100 {
            let s = Double(i) / 100
            let rejectsTheLeak = BargeInMonitor.floorForSensitivity(s) >= BargeInMonitor.loudestLeak
            XCTAssertEqual(BargeInMonitor.chunksForSensitivity(s), rejectsTheLeak ? 2 : 3, "s=\(s)")
        }
    }

    func testLoudnessCannotSeparateTheLeakFromAQuietVoice() {
        // The premise of the whole change: the loudest leak measured is louder
        // than the quietest voice measured, so no floor can split them.
        XCTAssertGreaterThan(BargeInMonitor.loudestLeak, Float(0.038))
    }

    // MARK: - The endpoint's wire shape
    //
    // None of this was covered before build 16. The two dialects disagree on
    // the path, on what the audio part is called, on where the model goes and
    // on what a voice is called, and every one of those drifts into a silent
    // 400 that looks like "the endpoint is broken".

    private func cfg(_ dialect: VoiceEndpoint.Dialect,
                     base: String = "https://voz.exemplo.net/v1",
                     model: String = "", voice: String = "", key: String? = nil)
    -> VoiceEndpoint.Config {
        .init(base: URL(string: base)!, model: model, voice: voice, key: key, dialect: dialect)
    }

    private func multipartNames(_ req: URLRequest) -> [String] {
        let body = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
        return body.components(separatedBy: "name=\"").dropFirst().compactMap {
            $0.components(separatedBy: "\"").first
        }
    }

    private func payload(_ req: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data())) as? [String: Any] ?? [:]
    }

    func testOpenAITranscriptionUsesItsOwnPathAndFieldName() {
        let r = VoiceEndpoint.transcribeRequest(Data([1, 2]), cfg(.openai, model: "whisper-1"),
                                                language: "pt")
        XCTAssertEqual(r.url?.path, "/v1/audio/transcriptions")
        XCTAssertEqual(r.httpMethod, "POST")
        let names = multipartNames(r)
        XCTAssertTrue(names.contains("file"), "\(names)")
        XCTAssertTrue(names.contains("model"), "\(names)")
        XCTAssertTrue(names.contains("language"), "\(names)")
    }

    func testFishTranscriptionUsesASRAndCallsTheFileAudio() {
        // Fish's /asr takes no model — the model rides a header, and only for
        // TTS — and a 400 saying exactly that is how this was found.
        let r = VoiceEndpoint.transcribeRequest(Data([1, 2]), cfg(.fish, model: "s2.1-pro"),
                                                language: "pt")
        XCTAssertEqual(r.url?.path, "/v1/asr")
        let names = multipartNames(r)
        XCTAssertTrue(names.contains("audio"), "\(names)")
        XCTAssertFalse(names.contains("file"), "\(names)")
        XCTAssertFalse(names.contains("model"), "\(names)")
        XCTAssertFalse(names.contains("language"), "\(names)")
    }

    func testNoLanguageMeansNoLanguageField() {
        // "Detect" has to omit the field rather than send an empty one, which
        // some gateways reject outright.
        let r = VoiceEndpoint.transcribeRequest(Data([1]), cfg(.openai), language: nil)
        XCTAssertFalse(multipartNames(r).contains("language"))
    }

    func testAnEmptyModelIsOmittedRatherThanSentBlank() {
        let r = VoiceEndpoint.transcribeRequest(Data([1]), cfg(.openai, model: ""), language: nil)
        XCTAssertFalse(multipartNames(r).contains("model"))
    }

    func testTheUploadedBytesSurviveTheMultipartWrapper() {
        let wav: [UInt8] = [0x52, 0x49, 0x46, 0x46, 0xFF, 0x00, 0xAB]
        let r = VoiceEndpoint.transcribeRequest(Data(wav), cfg(.openai), language: nil)
        XCTAssertTrue((r.httpBody ?? Data()).range(of: Data(wav)) != nil)
    }

    func testTheKeyBecomesABearerHeaderAndAnEmptyOneDoesNot() {
        let with = VoiceEndpoint.transcribeRequest(Data([1]), cfg(.openai, key: "abc"), language: nil)
        XCTAssertEqual(with.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
        let without = VoiceEndpoint.transcribeRequest(Data([1]), cfg(.openai, key: ""), language: nil)
        XCTAssertNil(without.value(forHTTPHeaderField: "Authorization"))
    }

    func testOpenAISynthesisNamesTheTextInputAndTheVoiceVoice() throws {
        let r = try VoiceEndpoint.speechRequest("olá", cfg(.openai, model: "tts-1", voice: "alloy"),
                                                container: .mp3)
        XCTAssertEqual(r.url?.path, "/v1/audio/speech")
        let p = payload(r)
        XCTAssertEqual(p["input"] as? String, "olá")
        XCTAssertEqual(p["voice"] as? String, "alloy")
        XCTAssertEqual(p["model"] as? String, "tts-1")
        XCTAssertEqual(p["response_format"] as? String, "mp3")
        XCTAssertNil(r.value(forHTTPHeaderField: "model"))
    }

    func testFishSynthesisNamesTheVoiceReferenceIdAndPutsTheModelInAHeader() throws {
        let r = try VoiceEndpoint.speechRequest("olá", cfg(.fish, model: "s2.1-pro", voice: "abc123"),
                                                container: .mp3)
        XCTAssertEqual(r.url?.path, "/v1/tts")
        let p = payload(r)
        XCTAssertEqual(p["text"] as? String, "olá")
        XCTAssertEqual(p["reference_id"] as? String, "abc123")
        XCTAssertNil(p["model"], "Fish carries the model in a header, not the body")
        XCTAssertEqual(r.value(forHTTPHeaderField: "model"), "s2.1-pro")
    }

    func testFishKeepsTheLatencySettingsThatBoughtTheFirstAudio() throws {
        // Left at Fish's defaults ("normal", 300) this was the slowest pair
        // available, and time-to-first-audio was the complaint that started the
        // whole streaming work.
        let p = payload(try VoiceEndpoint.speechRequest("olá", cfg(.fish), container: .wav))
        XCTAssertEqual(p["latency"] as? String, "balanced")
        XCTAssertEqual(p["chunk_length"] as? Int, 120)
    }

    func testStreamingAsksForWAVBecauseTheDecoderNeedsAStatedFormat() throws {
        // The buffered path can take mp3 — AVAudioPlayer sniffs the container.
        // The streaming path cannot: WAVStreamDecoder reads the wire format out
        // of the header rather than guessing, which is the whole reason a wrong
        // guess is not full-volume noise.
        for dialect in VoiceEndpoint.Dialect.allCases {
            let wav = payload(try VoiceEndpoint.speechRequest("a", cfg(dialect), container: .wav))
            let key = dialect == .fish ? "format" : "response_format"
            XCTAssertEqual(wav[key] as? String, "wav", "\(dialect)")
            let mp3 = payload(try VoiceEndpoint.speechRequest("a", cfg(dialect), container: .mp3))
            XCTAssertEqual(mp3[key] as? String, "mp3", "\(dialect)")
        }
    }

    func testTheSampleRateRidesOnlyOnFishAndOnlyForWAV() throws {
        // mp3 carries its own rate, and OpenAI's endpoint has no such field.
        XCTAssertEqual(payload(try VoiceEndpoint.speechRequest("a", cfg(.fish), container: .wav))["sample_rate"] as? Int, 24_000)
        XCTAssertNil(payload(try VoiceEndpoint.speechRequest("a", cfg(.fish), container: .mp3))["sample_rate"])
        XCTAssertNil(payload(try VoiceEndpoint.speechRequest("a", cfg(.openai), container: .wav))["sample_rate"])
    }

    func testABaseURLWithAPathKeepsIt() throws {
        // Users paste the whole prefix their gateway lives behind.
        let r = try VoiceEndpoint.speechRequest("a", cfg(.openai, base: "https://x.net/api/v1"),
                                                container: .mp3)
        XCTAssertEqual(r.url?.path, "/api/v1/audio/speech")
    }

    func testTranscriptIsReadFromEveryShapeSeenInTheWild() throws {
        XCTAssertEqual(try VoiceEndpoint.parseTranscript(Data(#"{"text":"oi"}"#.utf8)), "oi")
        XCTAssertEqual(try VoiceEndpoint.parseTranscript(Data(#"{"result":"oi"}"#.utf8)), "oi")
        XCTAssertEqual(try VoiceEndpoint.parseTranscript(Data(#"{"transcript":"oi"}"#.utf8)), "oi")
        XCTAssertEqual(try VoiceEndpoint.parseTranscript(Data("  oi \n".utf8)), "oi")
    }

    func testAnEmptyOrUnrecognisedBodyIsAFailureNotAnEmptyTranscript() {
        // Returning "" here would send a blank message on the user's behalf.
        XCTAssertThrowsError(try VoiceEndpoint.parseTranscript(Data()))
        XCTAssertThrowsError(try VoiceEndpoint.parseTranscript(Data("   ".utf8)))
        XCTAssertThrowsError(try VoiceEndpoint.parseTranscript(Data(#"{"error":"nope"}"#.utf8)))
    }

    // MARK: - Markdown tables

    func testTableSeparatorRowIsNotSpoken() {
        for rule in ["|---|---|", "| --- | :--- |", "|:-:|-:|"] {
            XCTAssertFalse(SpeechManager.isSpeakable(rule), "\(rule) is formatting")
        }
    }

    func testTableRowIsSpokenAsAListOfCells() {
        let row = "| **Duração** | 4 anos (1914-1918) | 6 anos (1939-1945) |"
        XCTAssertEqual(SpeechManager.spokenText(row),
                       "Duração, 4 anos (1914-1918), 6 anos (1939-1945)")
    }

    func testEmptyLeadingCellDoesNotProduceALeadingComma() {
        XCTAssertEqual(SpeechManager.spokenText("| | **Primeira** | **Segunda** |"),
                       "Primeira, Segunda")
    }

    func testOrdinarySentenceWithNoPipeIsUntouched() {
        XCTAssertEqual(SpeechManager.spokenText("- **Eixo** — Alemanha e Japão"),
                       "- Eixo — Alemanha e Japão")
    }
}
