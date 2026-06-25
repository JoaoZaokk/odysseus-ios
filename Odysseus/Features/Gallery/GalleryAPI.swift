import Foundation

extension APIClient {
    func galleryLibrary(limit: Int = 100) async throws -> [GalleryImage] {
        let data = try await send(request("/api/gallery/library?limit=\(limit)"))
        struct Wrap: Decodable { var items: [GalleryImage] }
        if let w = try? JSONDecoder().decode(Wrap.self, from: data) { return w.items }
        return decodeList(GalleryImage.self, data)
    }

    func galleryAlbums() async throws -> [GalleryAlbum] {
        decodeList(GalleryAlbum.self, try await send(request("/api/gallery/albums")))
    }

    func toggleGalleryFavorite(_ id: String) async throws {
        _ = try await send(request("/api/gallery/\(encPath(id))/favorite", method: "POST"))
    }

    /// Resolves an image/video URL (often relative) to an absolute URL.
    func mediaURL(_ raw: String) -> URL? { config.resolve(raw) }
}
