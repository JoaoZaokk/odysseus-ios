import Foundation

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

    func deleteEmailAccount(_ id: String) async throws {
        _ = try await send(request("/api/email/accounts/\(encPath(id))", method: "DELETE"))
    }

    func setDefaultEmailAccount(_ id: String) async throws {
        _ = try await send(request("/api/email/accounts/\(encPath(id))/set-default", method: "POST"))
    }
}
