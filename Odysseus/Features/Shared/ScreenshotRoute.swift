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

    /// `-voiceSay "…"`: the voice screen's first turn is this sentence, as if
    /// it had been heard, and the session ends when the reply does.
    /// `-voiceAutoStart YES` starts that session when the screen opens. For
    /// checking voice mode in the simulator, which has no voice to give it.
    static var voiceSay: String? {
        let v = UserDefaults.standard.string(forKey: "voiceSay")
        return (v?.isEmpty ?? true) ? nil : v
    }
    static var voiceAutoStart: Bool { UserDefaults.standard.string(forKey: "voiceAutoStart") != nil }

    /// `-chatSend "…"` with `chat:<id>`: that conversation sends this once its
    /// history is on screen. For checking where a long chat settles when a
    /// reply ends, without a tap.
    static var chatSend: String? {
        let v = UserDefaults.standard.string(forKey: "chatSend")
        return (v?.isEmpty ?? true) ? nil : v
    }

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
