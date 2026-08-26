import Foundation

/// A user-supplied speech endpoint, configured the same way an LLM is: a base
/// URL, an API key and a model name. Nothing is downloaded to the device and
/// nothing goes through the Odysseus server — the app talks straight to whatever
/// the user points it at (their own box, Fish Audio, any OpenAI-compatible
/// gateway).
///
/// The wire format is the OpenAI audio API, because that is what self-hosted
/// servers and hosted providers alike already speak:
///   STT  `POST {base}/audio/transcriptions`  multipart → `{"text": "…"}`
///   TTS  `POST {base}/audio/speech`          JSON      → raw audio bytes
///
/// This is deliberately separate from `APIClient`'s `/api/stt|tts/*` routes:
/// those are the Odysseus server's own speech services, which take no model and
/// no key. See `VoiceAPI.swift`.
enum VoiceEndpoint {

    // MARK: - Stored configuration

    /// Which half of the config a call needs. The two are configured (and keyed)
    /// independently so someone can run STT on their own box and TTS on a
    /// hosted voice, or either one alone.
    enum Kind: String {
        case stt, tts

        var urlKey: String { "voice.\(rawValue).endpoint.url" }
        var modelKey: String { "voice.\(rawValue).endpoint.model" }
        var voiceKey: String { "voice.\(rawValue).endpoint.voice" }
        /// Keychain, not UserDefaults: UserDefaults lands in the iCloud backup
        /// as plain text.
        var secretKey: String { "voice.\(rawValue).endpoint.key" }
        var dialectKey: String { "voice.\(rawValue).endpoint.dialect" }
        /// The chosen voice's human name, kept beside its id so Settings can
        /// show "Ana" instead of a 32-character reference_id.
        var voiceTitleKey: String { "voice.\(rawValue).endpoint.voiceTitle" }
    }

    /// Which wire format the endpoint speaks. Providers disagree on more than
    /// the path: field names, where the model goes, and what a voice is called
    /// all differ, so this can't be a single request shape with a swapped URL.
    enum Dialect: String, CaseIterable {
        case openai, fish

        var label: String {
            switch self {
            case .openai: return L("Compatível com OpenAI")
            case .fish:   return "Fish Audio"
            }
        }
    }

    struct Config {
        var base: URL
        var model: String
        var voice: String
        var key: String?
        var dialect: Dialect
    }

    /// nil when the user hasn't filled in a usable URL yet — the caller turns
    /// that into a readable message instead of firing a request at nothing.
    static func config(_ kind: Kind) -> Config? {
        let d = UserDefaults.standard
        let raw = (d.string(forKey: kind.urlKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        // Tolerate a pasted URL with no scheme ("meu.servidor/v1"), which is how
        // people usually copy them out of a dashboard.
        let normalized = raw.contains("://") ? raw : "https://\(raw)"
        guard var comps = URLComponents(string: normalized), comps.host != nil else { return nil }
        // A trailing slash would produce "…/v1//audio/speech" once we append.
        while comps.path.hasSuffix("/") { comps.path.removeLast() }
        guard let url = comps.url else { return nil }
        return Config(
            base: url,
            model: (d.string(forKey: kind.modelKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            voice: (d.string(forKey: kind.voiceKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            key: Keychain.get(kind.secretKey),
            dialect: Dialect(rawValue: d.string(forKey: kind.dialectKey) ?? "") ?? .openai
        )
    }

    static func isConfigured(_ kind: Kind) -> Bool { config(kind) != nil }

    // MARK: - Model discovery

    /// Asks the endpoint what it actually serves, instead of trusting a list
    /// hardcoded at build time. `GET {base}/models` is the OpenAI convention and
    /// OpenRouter, vLLM, LM Studio, Ollama's shim and most gateways answer it.
    ///
    /// Throws rather than returning empty when the endpoint has no such route
    /// (Fish's native API doesn't), so the caller can fall back to a known list
    /// instead of showing the user an empty picker.
    static func listModels(_ kind: Kind) async throws -> [String] {
        guard let cfg = config(kind) else { throw Failure.notConfigured }
        var req = URLRequest(url: cfg.base.appendingPathComponent("models"))
        if let k = cfg.key, !k.isEmpty { req.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }

        let (data, resp) = try await session().data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.http(status: status, body: snippet(data)) }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.noText(body: snippet(data))
        }
        // OpenAI/OpenRouter: {"data":[{"id":…}]}. A few servers answer a bare
        // {"models":[…]} of strings.
        if let rows = obj["data"] as? [[String: Any]] {
            return rows.compactMap { $0["id"] as? String }.sorted()
        }
        if let names = obj["models"] as? [String] { return names.sorted() }
        if let rows = obj["models"] as? [[String: Any]] {
            return rows.compactMap { ($0["id"] ?? $0["name"]) as? String }.sorted()
        }
        throw Failure.noText(body: snippet(data))
    }

    // MARK: - Fish catalogue

    /// The speech models Fish exposes through the `model:` header. Free-text
    /// entry is useless here — the names are exact and undiscoverable.
    static let fishModels = ["s2.1-pro", "s2.1-pro-free", "s2-pro", "s1"]

    /// One voice from Fish's library (or the user's own trained voices).
    /// `id` is the `reference_id` the synthesis call wants; `title` is what the
    /// settings row shows, since the id says nothing to a human.
    struct FishVoice: Identifiable, Hashable {
        let id: String
        let title: String
        let languages: [String]
        let author: String
    }

    /// The catalogue lives at the API root (`/model`), not under `/v1`, so the
    /// pasted base is walked back one level when it ends in `v1`.
    private static func fishRoot(_ base: URL) -> URL {
        // Walks off both "…/v1" and the compat layer's "…/compat/v1"; stripping
        // only one component left "…/compat/model", which 404s.
        var u = base
        while ["v1", "compat", "api"].contains(u.lastPathComponent) {
            u = u.deletingLastPathComponent()
        }
        return u
    }

    /// Lists voices, optionally narrowed to a language or to the workspace's own
    /// models — the two filters that matter when "Portuguese" would otherwise
    /// hand you a European voice.
    static func fishVoices(search: String = "", language: String? = nil,
                           mine: Bool = false) async throws -> [FishVoice] {
        guard let cfg = config(.tts) else { throw Failure.notConfigured }
        var comps = URLComponents(url: fishRoot(cfg.base).appendingPathComponent("model"),
                                  resolvingAgainstBaseURL: false)
        var q = [URLQueryItem(name: "page_size", value: "100"),
                 URLQueryItem(name: "sort_by", value: "score")]
        if !search.isEmpty { q.append(URLQueryItem(name: "title", value: search)) }
        if let language, !language.isEmpty { q.append(URLQueryItem(name: "language", value: language)) }
        if mine { q.append(URLQueryItem(name: "self", value: "true")) }
        comps?.queryItems = q
        guard let url = comps?.url else { throw Failure.notConfigured }

        var req = URLRequest(url: url)
        if let k = cfg.key, !k.isEmpty { req.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await session().data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.http(status: status, body: snippet(data)) }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]] else {
            throw Failure.noText(body: snippet(data))
        }
        return items.compactMap { it in
            guard let id = it["_id"] as? String, let title = it["title"] as? String else { return nil }
            // Voice-conversion models can't speak from text, so they'd only be
            // noise in a TTS picker.
            guard (it["type"] as? String) != "svc" else { return nil }
            return FishVoice(
                id: id,
                title: title,
                languages: (it["languages"] as? [String]) ?? [],
                author: ((it["author"] as? [String: Any])?["nickname"] as? String) ?? ""
            )
        }
    }

    // MARK: - Errors

    enum Failure: LocalizedError {
        case notConfigured
        case http(status: Int, body: String)
        case noText(body: String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return L("Endpoint de voz não configurado (falta a URL).")
            case let .http(status, body):
                // The body is the whole point: a 401 from Fish and a 404 from a
                // mistyped path look identical without it.
                return body.isEmpty ? L("Endpoint respondeu %d.", status)
                                    : L("Endpoint respondeu %d: %@", status, body)
            case let .noText(body):
                return L("Endpoint não devolveu texto. Resposta: %@", body)
            }
        }
    }

    /// Response bodies are echoed back into the UI, so cap them: a gateway that
    /// answers an HTML error page would otherwise fill the screen.
    private static func snippet(_ data: Data) -> String {
        let s = String(decoding: data.prefix(600), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.count > 400 ? String(s.prefix(400)) + "…" : s
    }

    /// One session for the whole feature. Building a fresh `URLSession` per call
    /// gave every request its own connection pool, so each sentence of a spoken
    /// reply paid a new TCP + TLS handshake against the same host.
    private static let sharedSession: URLSession = {
        let c = URLSessionConfiguration.default
        // Synthesis of a long reply, or transcription of a long recording, both
        // outrun the 30s default.
        c.timeoutIntervalForRequest = 120
        return URLSession(configuration: c)
    }()

    private static func session() -> URLSession { sharedSession }

    /// `URLSession` reports a cancelled request as `URLError.cancelled`, never
    /// as `CancellationError`, so `catch is CancellationError` silently misses
    /// it and a superseded request surfaces as a real failure.
    static func isCancellation(_ e: Error) -> Bool {
        if e is CancellationError { return true }
        return (e as? URLError)?.code == .cancelled
    }

    private static func authorized(_ url: URL, _ cfg: Config) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        if let k = cfg.key, !k.isEmpty { r.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
        return r
    }

    // MARK: - Speech → text

    /// Uploads a WAV and returns the transcript.
    static func transcribe(_ wav: Data) async throws -> String {
        guard let cfg = config(.stt) else { throw Failure.notConfigured }
        let isFish = cfg.dialect == .fish
        // Fish calls the file part "audio" and puts it under /asr; OpenAI calls
        // it "file" under /audio/transcriptions.
        let path = isFish ? "asr" : "audio/transcriptions"
        let filePart = isFish ? "audio" : "file"
        var req = authorized(cfg.base.appendingPathComponent(path), cfg)

        let boundary = "odysseus-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(filePart)\"; filename=\"audio.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n".utf8))
        // Fish takes no model on /asr (the model rides a header there, and only
        // for TTS). Elsewhere: send a model only when the user gave one rather
        // than inventing a default, since some gateways reject an unknown one.
        if !isFish, !cfg.model.isEmpty { field("model", cfg.model) }
        // Pinning the language is worth a lot: left to guess, Whisper-family
        // servers pick a random one on imperfect audio and hand back nothing —
        // the same reason the on-device engine stopped using "auto". Which
        // language comes from the speech setting, so a bilingual user can pin
        // one without moving the whole UI; only an explicit "detect" omits the
        // field and lets the server guess. Sent only in the OpenAI dialect,
        // where `language` (ISO-639-1) is documented; Fish's /asr is left alone
        // rather than fed a field verified only from its docs.
        if !isFish, let chosen = await MainActor.run(body: { SpeechLanguage.pinned() }) {
            field("language", chosen.iso639)
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        req.httpBody = body

        let (data, resp) = try await session().data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.http(status: status, body: snippet(data)) }

        // `{"text": …}` is the OpenAI shape; a few servers wrap it in
        // `{"result": …}` or answer with the bare string.
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for k in ["text", "transcript", "result"] {
                if let t = obj[k] as? String { return t }
            }
            throw Failure.noText(body: snippet(data))
        }
        let plain = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { throw Failure.noText(body: snippet(data)) }
        return plain
    }

    // MARK: - Text → speech

    /// Synthesizes `text` and returns the audio bytes (`AVAudioPlayer` sniffs the
    /// container, so the format only has to be something it knows).
    static func synthesize(_ text: String) async throws -> Data {
        guard let cfg = config(.tts) else { throw Failure.notConfigured }
        let isFish = cfg.dialect == .fish
        var req = authorized(cfg.base.appendingPathComponent(isFish ? "tts" : "audio/speech"), cfg)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any]
        if isFish {
            // Fish names the text "text", the voice "reference_id" (a voice
            // model id, including one you trained), and carries the model in a
            // header rather than the body.
            // `latency` and `chunk_length` are documented on Fish's own TTS
            // request and were being left at their defaults — "normal" and 300,
            // the slowest pair. "balanced" is the mode Fish's own SDK defaults
            // to for lowest time-to-first-audio, and a smaller chunk makes the
            // model emit its first audio sooner. Quality is unchanged in the
            // finished file; only the schedule moves.
            payload = ["text": text, "format": "mp3",
                       "latency": "balanced", "chunk_length": 120]
            if !cfg.voice.isEmpty { payload["reference_id"] = cfg.voice }
            if !cfg.model.isEmpty { req.setValue(cfg.model, forHTTPHeaderField: "model") }
        } else {
            payload = ["input": text, "response_format": "mp3"]
            if !cfg.model.isEmpty { payload["model"] = cfg.model }
            if !cfg.voice.isEmpty { payload["voice"] = cfg.voice }
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await session().data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.http(status: status, body: snippet(data)) }
        // A JSON body here means the server reported a problem with 200, which
        // some gateways do; audio never starts with '{'.
        guard data.first != UInt8(ascii: "{") else { throw Failure.noText(body: snippet(data)) }
        guard !data.isEmpty else { throw Failure.noText(body: "") }
        return data
    }

    // MARK: - Text → speech, streamed

    /// Same request, consumed as it arrives instead of all at once.
    ///
    /// The server was already streaming: `/v1/tts` answers with
    /// `Transfer-Encoding: chunked`, and `data(for:)` was quietly waiting for
    /// the last byte of it. This asks for `wav` — whose header states the wire
    /// format instead of leaving it to be guessed, see `WAVStreamDecoder` — and
    /// hands the caller each chunk as the socket delivers it.
    ///
    /// Cancelling the consuming task cancels the request.
    static func synthesizeStreaming(_ text: String) throws -> AsyncThrowingStream<Data, Error> {
        guard let cfg = config(.tts) else { throw Failure.notConfigured }
        let isFish = cfg.dialect == .fish
        var req = authorized(cfg.base.appendingPathComponent(isFish ? "tts" : "audio/speech"), cfg)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any]
        if isFish {
            // 24 kHz, not the 44.1 kHz default: WAV is uncompressed, and the
            // first device run moved 168 KB for a 29-character sentence — 8.8×
            // what the mp3 of the same sentence cost. Halving the rate halves
            // that, and 24 kHz is what OpenAI's own speech endpoint returns,
            // so it is not a quality corner being cut for speech.
            payload = ["text": text, "format": "wav", "sample_rate": 24_000,
                       "latency": "balanced", "chunk_length": 120]
            if !cfg.voice.isEmpty { payload["reference_id"] = cfg.voice }
            if !cfg.model.isEmpty { req.setValue(cfg.model, forHTTPHeaderField: "model") }
        } else {
            payload = ["input": text, "response_format": "wav"]
            if !cfg.model.isEmpty { payload["model"] = cfg.model }
            if !cfg.voice.isEmpty { payload["voice"] = cfg.voice }
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return ChunkedDelivery.shared.stream(req)
    }
}

/// Bridges `URLSessionDataDelegate` callbacks to an `AsyncThrowingStream`.
///
/// `URLSession.bytes(for:)` would avoid all of this, but it delivers one `UInt8`
/// per async step — around 88 000 of them per second of 44.1 kHz audio, which is
/// a lot of continuation machinery to run while the audio graph needs the CPU.
/// The delegate hands over whatever the socket read, which is what the decoder
/// wants anyway.
///
/// One shared session, not one per request: a session per request is the leak
/// that V-13 fixed for the non-streaming path, and it applies here too. The
/// delegate therefore keys its continuations by task identifier.
private final class ChunkedDelivery: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = ChunkedDelivery()

    private var session: URLSession!
    private var conts: [Int: AsyncThrowingStream<Data, Error>.Continuation] = [:]
    private let lock = NSLock()

    private override init() {
        super.init()
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        // Deliberately NOT waitsForConnectivity: it suspends the timeout, so
        // with no network the request never starts and never fails. The caller
        // has already marked the turn as speaking by then, and only a
        // completion or a failure releases it — a request that can never fail
        // parks the conversation in .speaking with the mic shut.
        // nil delegate queue: URLSession serialises callbacks on a queue of its
        // own, so per-task ordering is guaranteed without any work here.
        session = URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }

    func stream(_ req: URLRequest) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { cont in
            let task = session.dataTask(with: req)
            lock.withLock { conts[task.taskIdentifier] = cont }
            cont.onTermination = { _ in task.cancel() }
            task.resume()
        }
    }

    private func take(_ id: Int) -> AsyncThrowingStream<Data, Error>.Continuation? {
        lock.withLock { conts.removeValue(forKey: id) }
    }

    private func peek(_ id: Int) -> AsyncThrowingStream<Data, Error>.Continuation? {
        lock.withLock { conts[id] }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // The body would carry the server's explanation, but reading it
            // means letting the transfer continue; the status alone is what the
            // user is shown, and the non-streaming path already reports bodies.
            take(dataTask.taskIdentifier)?.finish(throwing: VoiceEndpoint.Failure.http(status: status, body: ""))
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        peek(dataTask.taskIdentifier)?.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let cont = take(task.taskIdentifier) else { return }
        if let error { cont.finish(throwing: error) } else { cont.finish() }
    }
}
