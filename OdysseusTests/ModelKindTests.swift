import XCTest
@testable import Odysseus

/// One Gemini key lists chat models next to text-to-speech, image and live-audio
/// ones, and the server hands them all to the picker as one flat inventory —
/// its Google probe keeps every model that answers `generateContent`, which the
/// TTS and image models do. Picking `gemini-3.8-flash-tts` for a chat fails at
/// send time. These pin which ids are which, so the picker offers chat models
/// and Settings can show the rest under their own headings.
final class ModelKindTests: XCTestCase {

    func testGeminiInventorySplitsIntoItsKinds() {
        let expect: [String: ModelKind] = [
            "gemini-3.1-pro-preview": .chat,
            "gemini-2.5-flash": .chat,
            "gemini-2.5-flash-lite": .chat,
            "gemma-3-27b-it": .chat,
            "gemma-3n-e4b-it": .chat,
            "aqa": .chat,
            "gemini-3.8-flash-tts": .tts,
            "gemini-2.5-pro-preview-tts": .tts,
            "gemini-2.5-flash-image": .image,
            "gemini-3-pro-image-preview": .image,
            "gemini-2.0-flash-preview-image-generation": .image,
            "imagen-4.0-generate-001": .image,
            "veo-3.0-generate-001": .video,
            "gemini-embedding-001": .embedding,
            "text-embedding-004": .embedding,
            "gemini-2.5-flash-native-audio-preview-09-2025": .realtime,
            "gemini-live-2.5-flash-preview": .realtime,
        ]
        for (id, kind) in expect {
            XCTAssertEqual(ModelKind.of(id), kind, id)
        }
    }

    func testOtherVendorsSpeechAndMediaModels() {
        let expect: [String: ModelKind] = [
            "gpt-4o-mini-tts": .tts,
            "tts-1-hd": .tts,
            "kokoro": .tts,
            "whisper-large-v3-turbo": .stt,
            "gpt-4o-transcribe": .stt,
            "openai/whisper-1": .stt,
            "gpt-realtime": .realtime,
            "gpt-image-1": .image,
            "dall-e-3": .image,
            "black-forest-labs/flux-1.1-pro": .image,
            "sora-2": .video,
            "nomic-embed-text": .embedding,
            "anthropic/claude-sonnet-5": .chat,
            "qwen3:8b": .chat,
            "meta-llama/llama-3.2-11b-vision-instruct": .chat,
            "deepseek-reasoner": .chat,
        ]
        for (id, kind) in expect {
            XCTAssertEqual(ModelKind.of(id), kind, id)
        }
    }

    /// Words that merely contain a trigger must not flip a chat model: "flux"
    /// inside a name, "image" as part of "imagine", a "live" in "deliver".
    func testSubstringsInsideWordsDoNotMisfire() {
        XCTAssertEqual(ModelKind.of("mistral-small-latest"), .chat)
        XCTAssertEqual(ModelKind.of("imagine-7b"), .chat)
        XCTAssertEqual(ModelKind.of("olive-13b"), .chat)
        XCTAssertEqual(ModelKind.of("ttsx-chat"), .chat)
    }

    /// The catalogue key each heading uses — every kind needs a title.
    func testEveryKindHasATitle() {
        for k in ModelKind.allCases { XCTAssertFalse(k.title.isEmpty, k.rawValue) }
    }

    /// The picker only offers chat models; everything else stays out even when
    /// the server lists it among the curated ones (its Google list matches
    /// "gemini-3" as a prefix, which catches "gemini-3.8-flash-tts").
    func testThePickerCarriesOnlyChatModels() {
        let out = APIClient.parseGroupedModels(Data(#"""
        {"items": [{"endpoint_id": "g", "endpoint_name": "Google Gemini", "model_type": "llm",
          "models": ["gemini-3.1-flash", "gemini-3.8-flash-tts", "gemini-3-pro-image-preview"],
          "models_extra": ["gemma-3-27b-it", "gemini-2.5-flash-native-audio-preview-09-2025"]}]}
        """#.utf8))
        XCTAssertEqual(out?.map(\.id), ["gemini-3.1-flash", "gemma-3-27b-it"])
    }

    /// A short inventory is shown whole: burying Gemma in "Outros modelos"
    /// because the server's curated Google list only names Gemini is what made
    /// it look unrecognised.
    func testAShortInventoryIsNotSplitIntoExtras() {
        let out = APIClient.parseGroupedModels(Data(#"""
        {"items": [{"endpoint_id": "g", "models": ["gemini-2.5-pro"], "models_extra": ["gemma-3-27b-it", "gemma-3-12b-it"]}]}
        """#.utf8))
        XCTAssertEqual(out?.map(\.isExtra), [false, false, false])
    }

    /// A long one still is — OpenRouter lists hundreds.
    func testALongInventoryKeepsItsExtrasApart() {
        let extras = (0..<60).map { "\"vendor/model-\($0)\"" }.joined(separator: ",")
        let out = APIClient.parseGroupedModels(Data(#"{"items": [{"endpoint_id": "or", "models": ["a/b"], "models_extra": [\#(extras)]}]}"#.utf8))
        XCTAssertEqual(out?.filter(\.isExtra).count, 60)
        XCTAssertEqual(out?.first?.isExtra, false)
    }
}
