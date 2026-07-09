import SwiftUI

/// A file uploaded via POST /api/upload (response `{files:[{id, ...}]}`).
struct UploadedFile: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var mime: String
    var width: Int?
    var height: Int?

    enum CodingKeys: String, CodingKey { case id, name, mime, width, height }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? id
        mime = (try? c.decode(String.self, forKey: .mime)) ?? "application/octet-stream"
        width = try? c.decodeIfPresent(Int.self, forKey: .width)
        height = try? c.decodeIfPresent(Int.self, forKey: .height)
    }

    var isImage: Bool { mime.hasPrefix("image/") }
}

extension APIClient {
    /// Uploads files and returns their server-side metadata (id, mime, …).
    func upload(_ files: [(data: Data, filename: String, mime: String)]) async throws -> [UploadedFile] {
        var form = MultipartForm()
        for f in files {
            form.append(file: "files", filename: f.filename, mime: f.mime, fileData: f.data)
        }
        var req = request("/api/upload", method: "POST")
        req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = form.finalizedData
        // streamSession: a large photo on a slow link can exceed the 30s resource cap.
        let data = try await send(req, via: streamSession)
        struct Wrap: Decodable { var files: [UploadedFile] }
        return (try? JSONDecoder().decode(Wrap.self, from: data))?.files ?? []
    }

    /// URL that serves an uploaded attachment by id.
    func attachmentURL(_ id: String) -> URL? { config.resolve("/api/upload/\(encPath(id))") }
}
