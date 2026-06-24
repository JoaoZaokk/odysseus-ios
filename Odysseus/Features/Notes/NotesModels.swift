import Foundation

/// A note from GET /api/notes. Created via POST /api/notes (JSON), updated via
/// PUT /api/notes/:id, deleted via DELETE.
struct Note: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var content: String
    var archived: Bool
    var pinned: Bool
    var dueDate: String?

    enum CodingKeys: String, CodingKey {
        case id, title, content, body, text
        case archived, pinned, important
        case dueDate = "due_date"
    }

    init(id: String = "", title: String = "", content: String = "",
         archived: Bool = false, pinned: Bool = false, dueDate: String? = nil) {
        self.id = id; self.title = title; self.content = content
        self.archived = archived; self.pinned = pinned; self.dueDate = dueDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) }
        else { id = UUID().uuidString }
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        content = (try? c.decode(String.self, forKey: .content))
            ?? (try? c.decode(String.self, forKey: .body))
            ?? (try? c.decode(String.self, forKey: .text)) ?? ""
        archived = (try? c.decode(Bool.self, forKey: .archived)) ?? false
        pinned = (try? c.decode(Bool.self, forKey: .pinned))
            ?? (try? c.decode(Bool.self, forKey: .important)) ?? false
        dueDate = try? c.decodeIfPresent(String.self, forKey: .dueDate)
    }
}

/// Body for create/update — only the fields the server expects.
struct NotePayload: Encodable {
    var title: String
    var content: String
    var archived: Bool?
    var pinned: Bool?
}
