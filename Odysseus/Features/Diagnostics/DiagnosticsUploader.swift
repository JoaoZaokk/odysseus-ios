import Foundation

/// Sends the spool to the owner's collector ("Zão Hub", the ZaoPrompt
/// telemetry-server contract plus `X-App-Id`/`X-App-Token`). Opt-in, and only
/// deletes local events after a 2xx, so a death mid-request loses nothing.
/// Backoff is persisted: a collector that is down does not get hammered on
/// every scene change.
enum DiagnosticsUploader {
    private static let nextTryKey = "diag.upload.nextTry"
    private static var inFlight = false

    static func flushIfEnabled() {
        let store = DiagnosticsStore.shared
        // The collector answers 400 without both headers, so an unset token means
        // "not configured yet", not "try anyway".
        guard store.isUploadEnabled, !store.appToken.isEmpty,
              let url = URL(string: store.endpoint), url.scheme == "https" else { return }
        guard Date().timeIntervalSince1970 >= UserDefaults.standard.double(forKey: nextTryKey) else { return }
        let events = store.recentEvents(limit: 500)
        guard !events.isEmpty, !inFlight else { return }
        inFlight = true
        let last = events.last!.ts
        let body: [String: Any] = [
            "app": DiagnosticsStore.appID,
            "installId": store.installId,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "device": deviceModel,
            "locale": Locale.current.identifier,
            "events": events.map { ["name": $0.name, "ts": $0.ts, "props": $0.props] as [String: Any] },
        ]
        var req = URLRequest(url: url.appendingPathComponent("v1/ingest"))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(DiagnosticsStore.appID, forHTTPHeaderField: "X-App-Id")
        req.setValue(store.appToken, forHTTPHeaderField: "X-App-Token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        Task {
            defer { inFlight = false }
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    store.drop(upTo: last)
                    UserDefaults.standard.set(0, forKey: nextTryKey)
                } else {
                    backoff()
                }
            } catch { backoff() }
        }
    }

    private static func backoff() {
        let prev = max(60, UserDefaults.standard.double(forKey: "diag.upload.backoff"))
        let next = min(prev * 2, 6 * 3600)
        UserDefaults.standard.set(next, forKey: "diag.upload.backoff")
        UserDefaults.standard.set(Date().timeIntervalSince1970 + next, forKey: nextTryKey)
    }

    static var deviceModel: String {
        var sys = utsname(); uname(&sys)
        return withUnsafePointer(to: &sys.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
    }
}
