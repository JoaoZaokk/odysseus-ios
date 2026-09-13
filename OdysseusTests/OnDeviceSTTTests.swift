import XCTest
@testable import Odysseus

/// The pure rules around the engine: the Core ML folder name whisper.cpp
/// derives (1.10 got it wrong for every quantized model), the encoder context
/// for short clips, and the memory gate.
final class OnDeviceSTTTests: XCTestCase {
    func testCoreMLEncoderPathMatchesWhisperCpp() {
        XCTAssertEqual(WhisperEngine.coreMLEncoderPath(forModelAt: "w-turbo-q5-ggml-large-v3-turbo-q5_0.bin"),
                       "w-turbo-q5-ggml-large-v3-turbo-encoder.mlmodelc")
        XCTAssertEqual(WhisperEngine.coreMLEncoderPath(forModelAt: "w-small-q5-ggml-small-q5_1.bin"),
                       "w-small-q5-ggml-small-encoder.mlmodelc")
        XCTAssertEqual(WhisperEngine.coreMLEncoderPath(forModelAt: "w-tiny-en-ggml-tiny.en.bin"),
                       "w-tiny-en-ggml-tiny.en-encoder.mlmodelc")
        XCTAssertEqual(WhisperEngine.coreMLEncoderPath(forModelAt: "/x/y/w-turbo-ggml-large-v3-turbo.bin"),
                       "/x/y/w-turbo-ggml-large-v3-turbo-encoder.mlmodelc")
        // Only the exact -qD_D shape is a quantization suffix.
        XCTAssertEqual(WhisperEngine.coreMLEncoderPath(forModelAt: "w-medium-q5-ggml-medium-q5_0.bin"),
                       "w-medium-q5-ggml-medium-encoder.mlmodelc")
        XCTAssertEqual(WhisperEngine.coreMLEncoderPath(forModelAt: "u-1-ggml-model-q8.bin"),
                       "u-1-ggml-model-q8-encoder.mlmodelc")
    }

    func testDownloadManagerUsesTheSameNameAndRemembersTheLegacyOne() {
        XCTAssertEqual(ModelDownloadManager.coreMLFolderName(id: "w-turbo-q5", filename: "ggml-large-v3-turbo-q5_0.bin"),
                       "w-turbo-q5-ggml-large-v3-turbo-encoder.mlmodelc")
        XCTAssertEqual(ModelDownloadManager.legacyCoreMLFolderName(id: "w-turbo-q5", filename: "ggml-large-v3-turbo-q5_0.bin"),
                       "w-turbo-q5-ggml-large-v3-turbo-q5_0-encoder.mlmodelc")
        // Unquantized models were already right, so legacy == current there.
        XCTAssertEqual(ModelDownloadManager.coreMLFolderName(id: "w-base", filename: "ggml-base.bin"),
                       ModelDownloadManager.legacyCoreMLFolderName(id: "w-base", filename: "ggml-base.bin"))
    }

    func testAudioContextFollowsTheClipWithinWhisperBounds() {
        XCTAssertEqual(WhisperEngine.audioContext(forSamples: 16_000 * 3), 768)      // 3 s → the streaming floor
        XCTAssertEqual(WhisperEngine.audioContext(forSamples: 16_000 * 20), 1064)    // 20 s → 1000 + 64
        XCTAssertEqual(WhisperEngine.audioContext(forSamples: 16_000 * 60), 1500)    // capped at the model
    }

    func testMemoryRequiredCountsTheCoreMLEncoderOnTop() {
        let turbo = VoiceModel(id: "w-turbo", name: "t", task: .stt, lang: .universal, bytes: 1_620_000_000, url: URL(string: "https://huggingface.co/a/b/resolve/main/c.bin")!)
        let bare = STTRunner.memoryRequired(for: turbo, coreMLBytes: 0)
        let withML = STTRunner.memoryRequired(for: turbo, coreMLBytes: 1_173_000_000)
        XCTAssertGreaterThan(bare, turbo.bytes)
        XCTAssertEqual(withML - bare, 1_173_000_000)
        #if os(macOS)
        XCTAssertNil(STTRunner.fits(turbo, coreMLBytes: 0), "no per-process limit is exposed on macOS")
        #endif
    }

    func testPromptOnlyForKnownLanguagesAndNeverForAuto() {
        XCTAssertNotNil(STTPrompt.forLanguage("pt"))
        XCTAssertNotNil(STTPrompt.forLanguage("en"))
        XCTAssertNil(STTPrompt.forLanguage("ja"))
        XCTAssertTrue(STTPrompt.forLanguage("pt")!.contains("um centavo"))
    }
}
