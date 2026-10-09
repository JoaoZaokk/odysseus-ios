import Foundation

/// The native counterpart of the web's Settings › Appearance "Customize UI"
/// checkboxes (`static/js/ui_visibility.js`): show or hide the parts of the
/// sidebar, the message field and the conversation that this app actually
/// has. Kept on this device — one UserDefaults key with the hidden ids —
/// the way the web keeps its map in localStorage. Everything is visible
/// until the user hides it, except the web's default-off keys (full width);
/// unknown ids are dropped on read so an old key can never hide something
/// that no longer exists.
struct UIVisibility: Equatable {
    static let storageKey = "ui.hidden"

    enum Group: String, CaseIterable, Identifiable {
        case sidebar, composer, chat
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sidebar: return "Barra lateral"
            case .composer: return "Campo de mensagem"
            case .chat: return "Conversa"
            }
        }
    }

    enum Key: String, CaseIterable, Identifiable {
        // Sidebar — the web's tool-research, tools-section and the per-tool rows.
        case deepSearch = "sidebar.deepSearch"
        case spaces = "sidebar.spaces"
        case brain = "sidebar.brain", notes = "sidebar.notes", calendar = "sidebar.calendar"
        case gallery = "sidebar.gallery", email = "sidebar.email", tasks = "sidebar.tasks"
        case library = "sidebar.library", compare = "sidebar.compare", cookbook = "sidebar.cookbook"
        // Message field — web-toggle-btn, research-btn, mode-toggle, attach-btn; the mic is native.
        case webChip = "composer.web", deepChip = "composer.deep", agentChip = "composer.agent"
        case attach = "composer.attach", mic = "composer.mic"
        // Conversation — show-thinking, chat-meta, welcome-text, chat-fullwidth.
        case thinking = "chat.thinking", modelName = "chat.modelName"
        case welcome = "chat.welcome", fullWidth = "chat.fullWidth"

        var id: String { rawValue }

        var group: Group {
            switch self {
            case .deepSearch, .spaces, .brain, .notes, .calendar, .gallery, .email, .tasks, .library, .compare, .cookbook: return .sidebar
            case .webChip, .deepChip, .agentChip, .attach, .mic: return .composer
            case .thinking, .modelName, .welcome, .fullWidth: return .chat
            }
        }

        /// Catalogue key. The section rows reuse `AppSection.title` so the
        /// toggle reads exactly like the row it hides.
        var title: String {
            switch self {
            case .deepSearch: return "Deep Search"
            case .spaces: return "Espaços"
            case .brain: return AppSection.brain.title
            case .notes: return AppSection.notes.title
            case .calendar: return AppSection.calendar.title
            case .gallery: return AppSection.gallery.title
            case .email: return AppSection.email.title
            case .tasks: return AppSection.tasks.title
            case .library: return AppSection.library.title
            case .compare: return AppSection.compare.title
            case .cookbook: return AppSection.cookbook.title
            case .webChip: return "Botão Web"
            case .deepChip: return "Botão Deep"
            case .agentChip: return "Botão Agente"
            case .attach: return "Anexar fotos"
            case .mic: return "Microfone"
            case .thinking: return "Raciocínio do modelo"
            case .modelName: return "Nome do modelo nas respostas"
            case .welcome: return "Texto de boas-vindas"
            case .fullWidth: return "Largura total"
            }
        }

        /// The one row that needs a second line: off means a 720 pt reading
        /// column, which only shows on iPad and Mac.
        var caption: String? {
            self == .fullWidth ? "Desligado: coluna de leitura no iPad e no Mac." : nil
        }

        /// The sidebar rows that hang off the "Espaços" master switch.
        var isSection: Bool { group == .sidebar && self != .deepSearch && self != .spaces }

        init(_ section: AppSection) {
            switch section {
            case .brain: self = .brain
            case .notes: self = .notes
            case .calendar: self = .calendar
            case .gallery: self = .gallery
            case .email: self = .email
            case .tasks: self = .tasks
            case .library: self = .library
            case .compare: self = .compare
            case .cookbook: self = .cookbook
            }
        }
    }

    /// Off until the user turns them on — the web's UI_VIS_DEFAULT_OFF
    /// (`chat-fullwidth`): a reading column is the default on iPad and Mac.
    static let defaultOff: Set<Key> = [.fullWidth]

    /// Default-on ids the user turned off.
    private(set) var hidden: Set<String>
    /// Default-off ids the user turned on, stored as "+id". A bare id of a
    /// default-off key is what an older build wrote for "off", and still
    /// reads as off.
    private(set) var shown: Set<String>

    init(raw: String) {
        var hidden = Set<String>(), shown = Set<String>()
        for token in raw.split(separator: ",").map(String.init) {
            let on = token.hasPrefix("+")
            guard let k = Key(rawValue: on ? String(token.dropFirst()) : token) else { continue }
            if Self.defaultOff.contains(k) { if on { shown.insert(k.rawValue) } }
            else if !on { hidden.insert(k.rawValue) }
        }
        self.hidden = hidden
        self.shown = shown
    }

    /// Sorted so the same set always serialises the same way.
    var raw: String { (hidden.sorted() + shown.sorted().map { "+" + $0 }).joined(separator: ",") }

    var isDefault: Bool { hidden.isEmpty && shown.isEmpty }

    /// Every key of the group is where it starts ("Restaurar padrão" has
    /// nothing to do).
    func isDefault(_ g: Group) -> Bool {
        Key.allCases.filter { $0.group == g }.allSatisfy { !hidden.contains($0.rawValue) && !shown.contains($0.rawValue) }
    }

    func isOn(_ k: Key) -> Bool {
        Self.defaultOff.contains(k) ? shown.contains(k.rawValue) : !hidden.contains(k.rawValue)
    }

    /// A section row is on only while "Espaços" is: hiding the group hides
    /// every row, the way the web's `tools-section` hides every `tool-*`.
    func shows(_ section: AppSection) -> Bool { isOn(.spaces) && isOn(Key(section)) }

    mutating func set(_ k: Key, on: Bool) {
        if Self.defaultOff.contains(k) {
            if on { shown.insert(k.rawValue) } else { shown.remove(k.rawValue) }
        } else {
            if on { hidden.remove(k.rawValue) } else { hidden.insert(k.rawValue) }
        }
    }

    mutating func reset(_ g: Group) {
        for k in Key.allCases where k.group == g { hidden.remove(k.rawValue); shown.remove(k.rawValue) }
    }
}
