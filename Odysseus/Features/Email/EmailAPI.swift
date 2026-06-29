import Foundation

/// A failed email connection test ({ ok: false, error }) surfaced as an error.
struct EmailTestError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension APIClient {
    func emailList(folder: String = "INBOX", limit: Int = 50) async throws -> EmailListResponse {
        let path = "/api/email/list?folder=\(encQuery(folder))&limit=\(limit)"
        return try decode(EmailListResponse.self, try await send(request(path)))
    }

    func emailRead(_ uid: String, folder: String = "INBOX") async throws -> EmailDetail {
        try decode(EmailDetail.self, try await send(request("/api/email/read/\(encPath(uid))?folder=\(encQuery(folder))")))
    }

    func emailMarkRead(_ uid: String) async {
        _ = try? await send(request("/api/email/mark-read/\(encPath(uid))", method: "POST"))
    }

    func emailArchive(_ uid: String) async throws {
        _ = try await send(request("/api/email/archive/\(encPath(uid))", method: "POST"))
    }

    func emailDelete(_ uid: String) async throws {
        _ = try await send(request("/api/email/delete/\(encPath(uid))", method: "POST"))
    }

    // MARK: - Accounts

    func emailAccounts() async throws -> [EmailAccount] {
        decodeList(EmailAccount.self, try await send(request("/api/email/accounts")))
    }

    func addEmailAccount(_ payload: EmailAccountPayload) async throws {
        let req = try jsonRequest("/api/email/accounts", method: "POST", body: payload)
        _ = try await send(req)
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
        _ = try await send(request("/api/email/accounts/\(encPath(id))", method: "DELETE"))
    }

    func setDefaultEmailAccount(_ id: String) async throws {
        _ = try await send(request("/api/email/accounts/\(encPath(id))/set-default", method: "POST"))
    }
}
