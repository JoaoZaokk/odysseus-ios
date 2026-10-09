#if DEBUG
import SwiftUI

/// Opens one screen at launch, for App Store captures: `-screenshotRoute <route>`
/// on the launch command line (it lands in `UserDefaults`). Debug builds only —
/// nothing here ships.
///
/// Routes: `list`, `newchat`, `chat:<session id>`, `voice:<session id>`,
/// `deepsearch`, `section:<AppSection raw value>`, `settings`, `theme`,
/// `spaces`, `compare:<question>`, `memory` (the "Nova memória" box).
enum ScreenshotRoute {
    static var raw: String? {
        let r = UserDefaults.standard.string(forKey: "screenshotRoute")
        return (r?.isEmpty ?? true) ? nil : r
    }

    /// The route's argument when it starts with `prefix:`.
    static func value(_ prefix: String) -> String? {
        guard let r = raw, r.hasPrefix(prefix + ":") else { return nil }
        return String(r.dropFirst(prefix.count + 1))
    }

    static func matches(_ name: String) -> Bool { raw == name }

    /// `-screenshotHost <name>`: the server name shown in the UI, so captures
    /// against the local stub do not read "127.0.0.1".
    static var hostLabel: String? {
        let h = UserDefaults.standard.string(forKey: "screenshotHost")
        return (h?.isEmpty ?? true) ? nil : h
    }

    /// Called once the conversation list has loaded.
    @MainActor
    static func applyMain(sessions: [ChatSession], workspace: WorkspaceStore, showSettings: inout Bool) {
        guard let r = raw else { return }
        if r == "newchat" { workspace.setPrimary(.newChat) }
        if r == "deepsearch" { workspace.setPrimary(.deepSearch) }
        if r == "settings" || r == "theme" { showSettings = true }
        if let id = value("chat") ?? value("voice"), let s = sessions.first(where: { $0.id == id }) {
            workspace.setPrimary(.chat(s))
        }
        if let raw = value("section"), let s = AppSection(rawValue: raw) { workspace.setPrimary(.section(s)) }
        if matches("memory") { workspace.setPrimary(.section(.brain)) }
        if value("compare") != nil { workspace.setPrimary(.section(.compare)) }
    }
}
#endif
