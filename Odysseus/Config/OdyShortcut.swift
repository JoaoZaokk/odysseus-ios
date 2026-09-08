import SwiftUI

/// The fixed macOS keyboard shortcuts — one table feeds both the bindings
/// and the read-only Ajustes › Atalhos list, so they cannot drift.
///
/// Mapped from the web's keymap onto Mac conventions (Ctrl → ⌘). Not
/// rebindable: the web's `keybinds` setting is a browser concern.
struct OdyShortcut: Identifiable {
    let id: String
    let label: String
    let key: KeyEquivalent
    let modifiers: EventModifiers

    var caps: [String] {
        var out: [String] = []
        if modifiers.contains(.control) { out.append("⌃") }
        if modifiers.contains(.option) { out.append("⌥") }
        if modifiers.contains(.shift) { out.append("⇧") }
        if modifiers.contains(.command) { out.append("⌘") }
        switch key {
        case .return: out.append("↩")
        case .escape: out.append("⎋")
        case .upArrow: out.append("↑")
        case .downArrow: out.append("↓")
        default: out.append(String(key.character).uppercased())
        }
        return out
    }
}

enum OdyShortcuts {
    static let newChat    = OdyShortcut(id: "new_session",    label: "Nova conversa",              key: "n",         modifiers: .command)
    static let search     = OdyShortcut(id: "search",         label: "Buscar na barra lateral",    key: "f",         modifiers: .command)
    static let settings   = OdyShortcut(id: "settings",       label: "Abrir ajustes",              key: ",",         modifiers: .command)
    static let deepSearch = OdyShortcut(id: "deep_search",    label: "Deep Search",                key: "d",         modifiers: [.command, .shift])
    static let nextChat   = OdyShortcut(id: "next_session",   label: "Próxima conversa",           key: .downArrow,  modifiers: [.command, .option])
    static let prevChat   = OdyShortcut(id: "prev_session",   label: "Conversa anterior",          key: .upArrow,    modifiers: [.command, .option])
    static let pinChat    = OdyShortcut(id: "star_session",   label: "Fixar conversa",             key: "s",         modifiers: [.command, .option])
    static let focusInput = OdyShortcut(id: "focus_input",    label: "Focar o campo de mensagem",  key: "/",         modifiers: .command)
    static let send       = OdyShortcut(id: "send",           label: "Enviar mensagem",            key: .return,     modifiers: .command)
    static let stop       = OdyShortcut(id: "cancel",         label: "Parar resposta",             key: ".",         modifiers: .command)

    static let groups: [(String, [OdyShortcut])] = [
        ("Navegação", [newChat, search, settings, deepSearch, nextChat, prevChat, pinChat]),
        ("Mensagem", [focusInput, send, stop]),
    ]
}

extension View {
    func keyboardShortcut(_ s: OdyShortcut) -> some View { keyboardShortcut(s.key, modifiers: s.modifiers) }
}
