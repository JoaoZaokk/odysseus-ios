import Foundation

/// One stored memory from GET /api/memory. The web client groups by `category`
/// (default "fact") and pins via `pinned`.
struct Memory: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var text: String
    var category: String
    var pinned: Bool

    enum CodingKeys: String, CodingKey {
        case id, text, content, category, pinned, important
    }

    init(id: String, text: String, category: String = "fact", pinned: Bool = false) {
        self.id = id; self.text = text; self.category = category; self.pinned = pinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) }
        else { id = UUID().uuidString }
        text = (try? c.decode(String.self, forKey: .text))
            ?? (try? c.decode(String.self, forKey: .content)) ?? ""
        category = (try? c.decode(String.self, forKey: .category)) ?? "fact"
        pinned = (try? c.decode(Bool.self, forKey: .pinned))
            ?? (try? c.decode(Bool.self, forKey: .important)) ?? false
    }
}
