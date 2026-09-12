import Foundation

/// A failed email connection test ({ ok: false, error }) surfaced as an error.
struct EmailTestError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Mirrors the server's `_friendly_email_auth_error` (which only covers Outlook):
/// turn the common IMAP/SMTP TLS-mode/port mismatch into actionable guidance.
/// Returns a localization KEY when matched (the views render it through
/// `Text(LocalizedStringKey:)`), else the raw error.
func emailFriendlyMessage(_ raw: String) -> String {
    let l = raw.lowercased()
    let tlsMismatch = l.contains("wrong version number")
        || l.contains("wrong_version_number")
        || l.contains("_ssl.c")
        || l.contains("[ssl:")
        || l.contains("socket error: eof")
    if tlsMismatch {
        return "Descompasso de TLS/porta. No IMAP use a porta 993 com STARTTLS desligado (SSL); no SMTP use 465 com SSL, ou 587 com STARTTLS. Não cruze porta com segurança."
    }
    return raw
}

func emailFriendlyMessage(_ error: Error) -> String {
    emailFriendlyMessage((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
}

/// The server returns `{ emails: [], error: "…" }` both when no account is set up
/// AND when a configured account fails to connect. Tell them apart so a real TLS
/// failure shows the error (not the "not configured" empty state).
func emailLooksNotConfigured(_ raw: String) -> Bool {
    let l = raw.lowercased()
    return l.contains("not configured") || l.contains("não configurado")
        || l.contains("no email account") || l.contains("no imap")
}

extension APIClient {
    func emailList(folder: String = "INBOX", limit: Int = 50) async throws -> EmailListResponse {
        let path = "/api/email/list?folder=\(encQuery(folder))&limit=\(limit)"
        return try decode(EmailListResponse.self, try await send(request(path)))
    }

    func emailRead(_ uid: String, folder: String = "INBOX") async throws -> EmailDetail {
        // `full` defaults to false server-side, which fetches only the first 384KB
        // of the body — a big HTML mail then renders cut off mid-tag, and nothing
        // in the response says it was truncated. Opening a mail is a deliberate
        // act and the body is the whole point of the screen, so pay for the
        // complete fetch (the list view is what stays cheap).
        let path = "/api/email/read/\(encPath(uid))?folder=\(encQuery(folder))&full=true"
        return try decode(EmailDetail.self, try await send(request(path)))
    }

    func emailMarkRead(_ uid: String) async {
        _ = try? await send(request("/api/email/mark-read/\(encPath(uid))", method: "POST"))
    }

    /// The three mail mutations answer 200 with `{"success": false, "error": …}`
    /// ("Email not found", "Mail operation failed") — read the body, or the row
    /// vanishes from the list while the message stays on the server.
    func emailArchive(_ uid: String) async throws {
        try expectOK(try await send(request("/api/email/archive/\(encPath(uid))", method: "POST")), fallback: "Mail operation failed")
    }

    func emailDelete(_ uid: String) async throws {
        // The server declares this route as DELETE (unlike mark-read/archive, which are
        // POST) — sending POST here returned 405 and swipe-to-delete always failed.
        try expectOK(try await send(request("/api/email/delete/\(encPath(uid))", method: "DELETE")), fallback: "Mail operation failed")
    }

    // MARK: - Accounts

    func emailAccounts() async throws -> [EmailAccount] {
        decodeList(EmailAccount.self, try await send(request("/api/email/accounts")))
    }

    func addEmailAccount(_ payload: EmailAccountPayload) async throws {
        let req = try jsonRequest("/api/email/accounts", method: "POST", body: payload)
        try expectOK(try await send(req), fallback: L("O servidor recusou a operação."))
    }

    /// Tests IMAP (and SMTP, if configured) without saving.
    /// POST /api/email/accounts/test → { ok: true } | { ok: false, error: "…" }.
    func testEmailAccount(_ payload: EmailAccountPayload) async throws {
        let data = try await send(jsonRequest("/api/email/accounts/test", method: "POST", body: payload))
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           (obj["ok"] as? Bool) == false {
            let msg = (obj["error"] as? String) ?? (obj["detail"] as? String) ?? "Falha no teste de conexão."
            throw EmailTestError(message: msg)
        }
    }

    func deleteEmailAccount(_ id: String) async throws {
        try expectOK(try await send(request("/api/email/accounts/\(encPath(id))", method: "DELETE")), fallback: L("O servidor recusou a operação."))
    }

    // Automation — per account (`?account_id=`), plain user routes.
    private func acct(_ id: String) -> String { id.isEmpty ? "" : "?account_id=\(encQuery(id))" }

    func emailAutomationConfig(accountId: String) async throws -> EmailAutomationConfig {
        try decode(EmailAutomationConfig.self, try await send(request("/api/email/config" + acct(accountId))))
    }
    func saveEmailAutomationConfig(_ c: EmailAutomationConfig, accountId: String) async throws {
        var req = request("/api/email/config" + acct(accountId), method: "PUT")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: c.payload(accountId: accountId))
        try expectOK(try await send(req), fallback: L("O servidor recusou a operação."))
    }
    func emailWritingStyle(accountId: String) async throws -> String {
        let d = (try? JSONSerialization.jsonObject(with: try await send(request("/api/email/style" + acct(accountId))))) as? [String: Any] ?? [:]
        return (d["style"] as? String) ?? ""
    }
    func saveEmailWritingStyle(_ style: String, accountId: String) async throws {
        struct B: Encodable { let style: String }
        try expectOK(try await send(try jsonRequest("/api/email/style" + acct(accountId), method: "PUT", body: B(style: style))), fallback: L("O servidor recusou a operação."))
    }
    /// Reads the Sent folder through the utility model; failures are a 200
    /// with success:false, so they are read out of the body.
    func extractEmailWritingStyle(sampleCount: Int = 15, accountId: String) async throws -> String {
        struct B: Encodable { let sample_count: Int }
        let data = try await send(try jsonRequest("/api/email/extract-style" + acct(accountId), method: "POST", body: B(sample_count: sampleCount)), via: streamSession)
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard d["success"] as? Bool == true else { throw APIError.transport((d["error"] as? String) ?? "extract-style") }
        return (d["style"] as? String) ?? ""
    }
    func unsubscribeScan(accountId: String, folder: String = "INBOX", limit: Int = 25) async throws -> UnsubscribeScan {
        var path = "/api/email/unsubscribe/scan?folder=\(encQuery(folder))&limit=\(limit)"
        if !accountId.isEmpty { path += "&account_id=\(encQuery(accountId))" }
        let r = try decode(UnsubscribeScan.self, try await send(request(path), via: streamSession))
        guard r.success else { throw APIError.transport(r.error ?? "scan") }
        return r
    }
    func unsubscribeExecute(uid: String, folder: String, accountId: String, moveToSpam: Bool = false) async throws {
        struct B: Encodable { let uid: String, folder: String, account_id: String?, method_index: Int, move_to_spam: Bool }
        let data = try await send(try jsonRequest("/api/email/unsubscribe/execute", method: "POST",
                                                  body: B(uid: uid, folder: folder, account_id: accountId.isEmpty ? nil : accountId,
                                                          method_index: 0, move_to_spam: moveToSpam)), via: streamSession)
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard d["success"] as? Bool == true else { throw APIError.transport((d["error"] as? String) ?? "unsubscribe") }
    }
    func unsubscribeCleanup(uids: [String], action: String, accountId: String, folder: String = "INBOX") async throws -> (changed: Int, failed: Int) {
        struct B: Encodable { let folder: String, account_id: String?, action: String, uids: [String] }
        let data = try await send(try jsonRequest("/api/email/unsubscribe/cleanup", method: "POST",
                                                  body: B(folder: folder, account_id: accountId.isEmpty ? nil : accountId, action: action, uids: uids)), via: streamSession)
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard d["success"] as? Bool == true else { throw APIError.transport((d["error"] as? String) ?? "cleanup") }
        return ((d["changed"] as? Int) ?? 0, (d["failed"] as? Int) ?? 0)
    }

    func setDefaultEmailAccount(_ id: String) async throws {
        try expectOK(try await send(request("/api/email/accounts/\(encPath(id))/set-default", method: "POST")), fallback: L("O servidor recusou a operação."))
    }
}
