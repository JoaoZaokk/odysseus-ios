import Foundation

/// The second adapter at `APIClient`'s transport seam.
///
/// `URLProtocol.registerClass` deliberately is not used here: it does not reach
/// a session built from `URLSessionConfiguration.default`, which is what both of
/// `APIClient`'s sessions are. The class has to arrive through
/// `configuration.protocolClasses`, which is what `APIClient(config:protocolClasses:)`
/// exists for.
///
/// Routes are matched on the request path (query ignored) so a test states the
/// endpoint it is answering, not the full URL.
final class StubTransport: URLProtocol {

    struct Reply {
        var status: Int
        var body: Data
        var headers: [String: String]

        init(_ status: Int = 200, _ body: Data = Data(), headers: [String: String] = [:]) {
            self.status = status; self.body = body; self.headers = headers
        }

        static func json(_ raw: String, status: Int = 200) -> Reply {
            Reply(status, Data(raw.utf8), headers: ["Content-Type": "application/json"])
        }

        /// An SSE body delivered as one chunk. `bytes(for:)` splits it into lines
        /// regardless of how the transport chunks it.
        static func sse(_ frames: [String]) -> Reply {
            Reply(200, Data(frames.map { "data: \($0)\n\n" }.joined().utf8),
                  headers: ["Content-Type": "text/event-stream"])
        }
    }

    /// path → reply. Set before constructing the client; cleared by `reset()`.
    nonisolated(unsafe) private static var routes: [String: Reply] = [:]
    /// Every path this transport was asked for, in order.
    nonisolated(unsafe) private(set) static var seen: [String] = []
    /// The bodies the app sent, by path — so a test can assert what was written.
    nonisolated(unsafe) private(set) static var sentBodies: [String: Data] = [:]
    private static let lock = NSLock()

    static func route(_ path: String, _ reply: Reply) {
        lock.lock(); defer { lock.unlock() }
        routes[path] = reply
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        routes = [:]; seen = []; sentBodies = [:]
    }

    static func requested(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return seen.contains(path)
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.lock.lock()
        Self.seen.append(path)
        // `httpBody` is nil for a body set through a stream (multipart uploads),
        // so fall back to draining the stream.
        if let b = request.httpBody { Self.sentBodies[path] = b }
        else if let s = request.httpBodyStream { Self.sentBodies[path] = Self.drain(s) }
        let reply = Self.routes[path]
        Self.lock.unlock()

        guard let reply else {
            client?.urlProtocol(self, didFailWithError: URLError(
                .unsupportedURL,
                userInfo: [NSLocalizedDescriptionKey: "StubTransport has no route for \(path)"]))
            return
        }

        let resp = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                   httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty { client?.urlProtocol(self, didLoad: reply.body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream) -> Data {
        stream.open(); defer { stream.close() }
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            out.append(buf, count: n)
        }
        return out
    }
}
