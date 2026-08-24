import Foundation

/// What the server's own speech services report about themselves
/// (`GET /api/tts/stats`, `GET /api/stt/stats`).
///
/// Both services are optional and admin-configured, so `available` is false far
/// more often than not — the Settings screen reads this to say *why* the server
/// engine can't be used instead of letting the user pick it and hit a 503.
struct SpeechServiceStats: Decodable {
    var available: Bool
    var provider: String?
    var model: String?
    /// TTS only — the voice the server is configured to speak with. The synth
    /// endpoint takes no voice parameter, so this is informational: it tells the
    /// user which voice they'll get rather than letting them choose one.
    var voice: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available = (try? c.decode(Bool.self, forKey: .available)) ?? false
        provider = try? c.decodeIfPresent(String.self, forKey: .provider)
        model = try? c.decodeIfPresent(String.self, forKey: .model)
        voice = try? c.decodeIfPresent(String.self, forKey: .voice)
    }

    enum CodingKeys: String, CodingKey { case available, provider, model, voice }

    /// One line for the Settings footer: "openai · tts-1 · nova".
    var summary: String {
        [provider, model, voice].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }
}

extension APIClient {
    // MARK: - Server TTS

    /// Whether the server can synthesize speech, and with what.
    /// Returns nil when the endpoint isn't reachable at all (older servers built
    /// without the speech routes 404 here) — the caller treats that as "no
    /// server engine" rather than "temporarily unavailable".
    func ttsStats() async -> SpeechServiceStats? {
        guard let data = try? await send(request("/api/tts/stats")) else { return nil }
        return try? JSONDecoder().decode(SpeechServiceStats.self, from: data)
    }

    /// Synthesizes `text` server-side and returns the audio (WAV or MP3 — the
    /// route sniffs its own magic bytes, and `AVAudioPlayer` detects the format).
    ///
    /// Takes no voice or language: the server speaks with whatever its admin
    /// configured. That's the whole contract — `TTSRequest` is `{text, format}`.
    ///
    /// Rides `streamSession`: synthesis of a long reply can easily outrun the
    /// default session's 30s whole-transfer cap.
    func synthesizeSpeech(_ text: String) async throws -> Data {
        var req = request("/api/tts/synthesize", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text, "format": "audio"])
        return try await send(req, via: streamSession)
    }

    // MARK: - Server STT

    func sttStats() async -> SpeechServiceStats? {
        guard let data = try? await send(request("/api/stt/stats")) else { return nil }
        return try? JSONDecoder().decode(SpeechServiceStats.self, from: data)
    }

    /// Uploads a recording and returns its transcription (`{"text": "…"}`).
    /// The audio is sent as a WAV file part named `file`, which is what
    /// `UploadFile = File(...)` expects.
    func transcribeAudio(_ wav: Data) async throws -> String {
        var form = MultipartForm(fields: [:])
        form.append(file: "file", filename: "audio.wav", mime: "audio/wav", fileData: wav)
        var req = request("/api/stt/transcribe", method: "POST")
        req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = form.finalizedData
        let data = try await send(req, via: streamSession)
        struct Wrap: Decodable { var text: String? }
        return (try? JSONDecoder().decode(Wrap.self, from: data))?.text ?? ""
    }
}
