import SwiftUI

/// The app's shared settings-shaped chrome and its error vocabulary.
///
/// It lived at the bottom of `SettingsAdminSections.swift` — a 1013-line file
/// holding five unrelated layers — while ten files outside Settings imported it
/// (Email, Diffusion, Research, Tasks, Library, Cookbook, Compare, Speech and
/// the settings screens themselves). A module the whole app depends on should
/// not be reachable only by scrolling past someone else's view models.

enum SettingsUI {
    static func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? e.localizedDescription }

    /// Delivers data to the user as a file. Returns `true` when it was actually
    /// delivered, `false` on failure, `nil` when the user cancelled — so callers
    /// can report honestly. The old iOS branch wrote into tmp (unreachable, and
    /// purged by the OS) and the caller still announced "Backup exportado.";
    /// anyone trusting that phantom backup before a Danger-Zone wipe lost data.
    @MainActor
    static func saveJSON(_ data: Data, suggested: String) async -> Bool? {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do { try data.write(to: url); return true } catch { return false }
        #else
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suggested)
        do { try data.write(to: url) } catch { return false }
        // Find the topmost view controller and hand the file to the share sheet.
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              var top = scene.keyWindow?.rootViewController else { return false }
        while let presented = top.presentedViewController { top = presented }
        return await withCheckedContinuation { cont in
            let avc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            avc.completionWithItemsHandler = { _, completed, _, error in
                try? FileManager.default.removeItem(at: url)
                if error != nil { cont.resume(returning: false) }
                else { cont.resume(returning: completed ? true : nil) }
            }
            // iPad requires a popover anchor or UIKit crashes the app.
            avc.popoverPresentationController?.sourceView = top.view
            avc.popoverPresentationController?.sourceRect = CGRect(
                x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            avc.popoverPresentationController?.permittedArrowDirections = []
            top.present(avc, animated: true)
        }
        #endif
    }

    @ViewBuilder
    static func field(_ label: String, _ bind: Binding<String>, placeholder: String, theme: Theme,
                      numeric: Bool = false, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(label)).font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
            Group {
                if secure { SecureField(LocalizedStringKey(placeholder), text: bind) }
                else { TextField(LocalizedStringKey(placeholder), text: bind) }
            }
            .textFieldStyle(.plain).font(.ody(.subheadline)).foregroundStyle(theme.fg)
            .autocorrectionDisabled()
            // `numeric` used to be accepted and ignored — six ports and timeouts
            // asked for a number pad and got the full keyboard. Both modifiers
            // are no-ops on macOS via PlatformCompat.
            .keyboardType(numeric ? .numberPad : .default)
            // Every field here is an address, a host, a user name or a key. iOS
            // capitalizing the first character of those is always wrong.
            .textInputAutocapitalization(.never)
            .padding(9).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
        }
    }

    @ViewBuilder
    /// Variant whose options carry an id alongside the label, for menus over
    /// server objects. The String-only version below hands the caller back the
    /// display label, which forces a reverse lookup by name — fine for constant
    /// options, wrong for anything the server names, where two rows can share a
    /// name and the app would save the wrong id.
    static func menuRow(_ label: String, value: String, options: [(id: String, label: String)],
                        theme: Theme, _ pick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(label)).font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
            Menu {
                ForEach(options, id: \.id) { o in Button(LocalizedStringKey(o.label)) { pick(o.id) } }
            } label: {
                HStack {
                    Text(LocalizedStringKey(value)).font(.ody(.subheadline)).foregroundStyle(theme.fg).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.ody(size: 9)).foregroundStyle(theme.secondaryText)
                }
                .padding(9).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
            }
        }
    }

    static func menuRow(_ label: String, value: String, options: [String], theme: Theme, _ pick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(label)).font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
            Menu {
                ForEach(options, id: \.self) { o in Button(o) { pick(o) } }
            } label: {
                HStack {
                    Text(value).font(.ody(.subheadline)).foregroundStyle(theme.fg).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.ody(size: 9)).foregroundStyle(theme.secondaryText)
                }
                .padding(9).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
            }
        }
    }

    static func saveButton(theme: Theme, label: String = "Salvar", _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(label)).font(.ody(.subheadline, weight: .semibold))
                .padding(.horizontal, 16).padding(.vertical, 8).foregroundStyle(.white)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
