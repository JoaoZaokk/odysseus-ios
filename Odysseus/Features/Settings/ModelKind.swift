import Foundation

/// What a model id is *for*.
///
/// The server hands the client one flat inventory per endpoint. On a Gemini key
/// that is chat models next to text-to-speech, image and live-audio ones: its
/// Google probe keeps every model that answers `generateContent`
/// (`routes/model_routes.py`, `_google_model_supports_chat`), and the TTS and
/// image models do. Its curated Google list then matches "gemini-3" as a
/// prefix, so `gemini-3.8-flash-tts` lands in the picker's *main* list — and
/// choosing it for a chat fails at send time.
///
/// The server keeps no per-model capability for this route, so the id is all
/// there is to go on. The web does the same (`_vlExclude`, the TTS provider's
/// `['tts','audio']` keyword scan); this is that idea in one place, matched on
/// word boundaries so "olive" is not "live" and "imagine" is not "image".
enum ModelKind: String, CaseIterable, Identifiable {
    case chat, image, video, music, tts, stt, realtime, embedding

    var id: String { rawValue }

    /// Section heading in Settings.
    var title: String {
        switch self {
        case .chat:      return L("Chat")
        case .image:     return L("Imagem")
        case .video:     return L("Vídeo")
        case .music:     return L("Música")
        case .tts:       return L("Voz (TTS)")
        case .stt:       return L("Transcrição (STT)")
        case .realtime:  return L("Áudio ao vivo")
        case .embedding: return L("Embeddings")
        }
    }

    var symbol: String {
        switch self {
        case .chat:      return "bubble.left.and.bubble.right"
        case .image:     return "photo"
        case .video:     return "film"
        case .music:     return "music.note"
        case .tts:       return "speaker.wave.2"
        case .stt:       return "waveform"
        case .realtime:  return "dot.radiowaves.left.and.right"
        case .embedding: return "square.stack.3d.up"
        }
    }

    /// Checked in this order: a name can carry two cues ("…-native-audio-…-tts"
    /// does not exist, but "whisper" inside an embedding repo might), and the
    /// narrower purpose wins.
    private static let rules: [(ModelKind, [String])] = [
        (.embedding, ["embedding", "embed", "bge", "e5"]),
        (.stt,       ["whisper", "transcribe", "transcription", "stt", "asr", "parakeet"]),
        (.tts,       ["tts", "kokoro", "piper", "orpheus"]),
        (.realtime,  ["realtime", "native-audio", "live", "audio-preview"]),
        (.video,     ["veo", "sora", "video", "kling", "wan2", "hunyuanvideo", "cogvideox"]),
        // Google's music model family. Not voice: it cannot read a reply aloud.
        (.music,     ["lyria", "musicgen"]),
        // "nano-banana" is Google's image model under its public nickname —
        // the owner's real inventory lists "nano-banana-pro-preview" with no
        // "image" anywhere in it.
        (.image,     ["image", "imagen", "nano-banana", "dall-e", "flux", "stable-diffusion", "sdxl", "sd3",
                      "ideogram", "recraft", "seedream", "midjourney"]),
    ]

    /// "9 Chat · 3 Voz (TTS) · 2 Imagem" — empty when every model is a chat
    /// model, where a breakdown would only repeat the total.
    static func breakdown(_ ids: [String]) -> String {
        let counts = Dictionary(grouping: ids, by: of).mapValues(\.count)
        guard counts.keys.contains(where: { $0 != .chat }) else { return "" }
        return allCases.compactMap { k in counts[k].map { "\($0) \(k.title)" } }
            .joined(separator: " · ")
    }

    static func of(_ id: String) -> ModelKind {
        let name = id.lowercased()
        // Word boundaries: anything that is not a letter or digit. Checking the
        // token list (and multi-token cues against the joined text) keeps a cue
        // from matching inside another word.
        let tokens = name.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let joined = "-" + tokens.joined(separator: "-") + "-"
        for (kind, cues) in rules {
            for cue in cues {
                if cue.contains("-") {
                    if joined.contains("-" + cue + "-") { return kind }
                } else if tokens.contains(cue) {
                    return kind
                }
            }
        }
        return .chat
    }
}
