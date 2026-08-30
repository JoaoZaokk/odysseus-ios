import XCTest
@testable import Odysseus

/// Ajustes › Voz › Idioma da fala reached three of the four speech engines. The
/// server engine uploaded the audio and nothing else, so Whisper guessed — and
/// on short or noisy audio it guesses badly, answering a English-speaking user
/// in Portuguese or Spanish (issue #9).
final class ServerSTTLanguageTests: XCTestCase {

    private func body(language: String?) -> String {
        var form = MultipartForm(fields: language.map { ["language": $0] } ?? [:])
        form.append(file: "file", filename: "audio.wav", mime: "audio/wav",
                    fileData: Data("RIFF".utf8))
        return String(decoding: form.finalizedData, as: UTF8.self)
    }

    func testPinnedLanguageRidesAlongWithTheAudio() {
        let sent = body(language: "en")
        XCTAssertTrue(sent.contains("name=\"language\""), "no language part")
        XCTAssertTrue(sent.contains("\r\n\r\nen\r\n"), "language part is not the code")
    }

    /// "Detectar automaticamente" has to send nothing rather than a placeholder:
    /// an empty `language` is not the same request as no `language` at all, and
    /// asking Whisper to detect is a legitimate choice the user can make.
    func testDetectAutomaticallySendsNoLanguagePart() {
        XCTAssertFalse(body(language: nil).contains("name=\"language\""))
    }

    /// The audio part keeps the name the server binds (`UploadFile = File(...)`
    /// on `file`), whether or not a language rides with it.
    func testAudioPartIsStillNamedFile() {
        for lang in [nil, "pt"] {
            let sent = body(language: lang)
            XCTAssertTrue(sent.contains("name=\"file\"; filename=\"audio.wav\""))
            XCTAssertTrue(sent.contains("Content-Type: audio/wav"))
        }
    }

    /// Both server-side engines resolve the language the same way, so picking a
    /// language does not mean two different things depending on which one is on.
    func testBothServerEnginesAgreeOnTheWireField() {
        let cfg = VoiceEndpoint.Config(base: URL(string: "https://example.invalid")!,
                                       model: "whisper-1", voice: "", key: nil, dialect: .openai)
        let req = VoiceEndpoint.transcribeRequest(Data("RIFF".utf8), cfg, language: "en")
        let sent = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(sent.contains("name=\"language\""))
        XCTAssertTrue(body(language: "en").contains("name=\"language\""))
    }
}
