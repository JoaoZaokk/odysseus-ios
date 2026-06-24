import Foundation

/// An image (or video) from GET /api/gallery/library. `url` may be relative to
/// the server, so resolve it against the base URL before loading.
struct GalleryImage: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var url: String
    var prompt: String
    var filename: String
    var model: String?
    var favorite: Bool
    var width: Int?
    var height: Int?

    enum CodingKeys: String, CodingKey {
        case id, url, prompt, filename, model, favorite, width, height
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) }
        else { id = UUID().uuidString }
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
        prompt = (try? c.decode(String.self, forKey: .prompt)) ?? ""
        filename = (try? c.decode(String.self, forKey: .filename)) ?? ""
        model = try? c.decodeIfPresent(String.self, forKey: .model)
        favorite = (try? c.decode(Bool.self, forKey: .favorite)) ?? false
        width = try? c.decodeIfPresent(Int.self, forKey: .width)
        height = try? c.decodeIfPresent(Int.self, forKey: .height)
    }

    var isVideo: Bool {
        let lower = (filename.isEmpty ? url : filename).lowercased()
        return lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.hasSuffix(".webm")
    }
}

/// An album from GET /api/gallery/albums.
struct GalleryAlbum: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var coverURL: String?
    var count: Int

    enum CodingKeys: String, CodingKey {
        case id, name, title
        case coverURL = "cover_url"
        case count, image_count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) }
        else { id = UUID().uuidString }
        name = (try? c.decode(String.self, forKey: .name))
            ?? (try? c.decode(String.self, forKey: .title)) ?? "Álbum"
        coverURL = try? c.decodeIfPresent(String.self, forKey: .coverURL)
        count = (try? c.decode(Int.self, forKey: .count))
            ?? (try? c.decode(Int.self, forKey: .image_count)) ?? 0
    }
}
