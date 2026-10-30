import SwiftUI

// MARK: - Model

struct CookbookPackage: Decodable, Identifiable, Hashable, Sendable {
    var name: String
    var desc: String
    var category: String
    var kind: String?
    var pip: String?          // pip target, e.g. "hf_transfer", "diffusers[torch]"
    var target: String?       // "remote" | "local"
    var installed: Bool

    var id: String { name }
    /// Only pip-based packages can be installed with the simple one-shot command.
    var canInstall: Bool { !(pip ?? "").isEmpty && !installed }

    enum CodingKeys: String, CodingKey {
        case name, desc, category, kind, pip, target, installed, is_installed
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? "?"
        desc = (try? c.decode(String.self, forKey: .desc)) ?? ""
        category = (try? c.decode(String.self, forKey: .category)) ?? "Outros"
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        pip = try? c.decodeIfPresent(String.self, forKey: .pip)
        target = try? c.decodeIfPresent(String.self, forKey: .target)
        installed = (try? c.decode(Bool.self, forKey: .installed))
            ?? (try? c.decode(Bool.self, forKey: .is_installed)) ?? false
    }
}

// MARK: - API

extension APIClient {
    func cookbookPackages() async throws -> [CookbookPackage] {
        decodeList(CookbookPackage.self, try await send(request("/api/cookbook/packages")))
    }

    /// Installs a pip package by handing the server the exact shell command to run
    /// (matches the web Cookbook: POST /api/model/serve `{repo_id, cmd}`).
    ///
    /// `repo_id` is a *task id*, not the pip target: for a `pip install` command
    /// the server validates it against `[A-Za-z0-9][A-Za-z0-9._\-\[\]<>=!,~]*`
    /// (routes/cookbook_routes.py) and answers 400 "Invalid pip package name"
    /// for a space, `+`, `:` or `/`. 1.9 sent the whole pip spec there, so the
    /// four catalogue entries with several packages or a git+https URL
    /// (diffusers, krea_diffusers, boogu_image_mlx, sam_mask) could never be
    /// installed from the app. Each pip token is quoted on its own.
    ///
    /// The server reports "tmux/docker missing on the target" as HTTP 200 with
    /// `{ok: false, error}`, so the body is read rather than discarded.
    func installCookbookPackage(_ pkg: CookbookPackage) async throws {
        let pip = pkg.pip ?? ""
        let tokens = pip.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        guard !tokens.isEmpty else { throw APIError.transport("Pacote sem alvo pip.") }
        struct Body: Encodable { let repo_id: String; let cmd: String }
        let quoted = tokens.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let cmd = "python3 -m pip install --user --break-system-packages " + quoted.joined(separator: " ")
        // The server's check is ASCII (`[A-Za-z0-9][A-Za-z0-9._\-…]*`): "ç" or "中"
        // would be a 400 again, and the first character may not be `_`.
        var taskID = String(pkg.name.map { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "." || $0 == "-" ? $0 : "_" })
        while let f = taskID.first, !(f.isASCII && (f.isLetter || f.isNumber)) { taskID.removeFirst() }
        if taskID.isEmpty { taskID = "package" }
        let req = try jsonRequest("/api/model/serve", method: "POST",
                                  body: Body(repo_id: taskID, cmd: cmd))
        try expectOK(try await send(req), fallback: L("O servidor recusou a operação."))
    }

    /// Exposed for tests: the exact command the server is asked to run.
    static func cookbookInstallCommand(for pip: String) -> String {
        let tokens = pip.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        let quoted = tokens.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return "python3 -m pip install --user --break-system-packages " + quoted.joined(separator: " ")
    }
}

// MARK: - View

@MainActor
final class CookbookViewModel: ObservableObject {
    @Published var packages: [CookbookPackage] = []
    @Published var loading = false
    @Published var error: String?
    @Published var installing: Set<String> = []
    @Published var note: String?

    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func install(_ pkg: CookbookPackage) async {
        installing.insert(pkg.id); note = nil; error = nil
        defer { installing.remove(pkg.id) }
        do {
            try await api.installCookbookPackage(pkg)
            note = L("Instalação de %@ iniciada no servidor — pode levar alguns minutos.", pkg.name)
            // Poll for the real thing rather than sleeping once: a `pip install`
            // of something like diffusers[torch] runs for minutes, and a spinner
            // tied to a 4-second sleep always appeared to finish while the job was
            // still going — inviting a second tap and a duplicate install.
            for _ in 0..<24 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await load()
                if packages.first(where: { $0.id == pkg.id })?.installed == true { break }
            }
        } catch {
            self.error = L("Falha ao instalar %@: %@", pkg.name, SettingsUI.msg(error))
        }
    }

    var grouped: [(category: String, items: [CookbookPackage])] {
        let buckets = Dictionary(grouping: packages) { $0.category }
        return buckets.map { (category: $0.key, items: $0.value) }.sorted { $0.category < $1.category }
    }

    func load() async {
        loading = true; defer { loading = false }
        do { packages = try await api.cookbookPackages(); error = nil }
        catch let e where e.isCancellation {}
        catch { self.error = SettingsUI.msg(error) }
    }
}

struct CookbookView: View {
    @StateObject private var vm: CookbookViewModel
    @Environment(\.theme) private var theme
    init(app: AppState) { _vm = StateObject(wrappedValue: CookbookViewModel(api: app.api)) }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            content
        }
        .screenChrome(title: "Cookbook")
        .task { await vm.load() }
        .odyRefreshable { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.packages.isEmpty && vm.loading {
            ProgressView().tint(theme.accent)
        } else if vm.packages.isEmpty, let e = vm.error {
            // A failed first load said "Pacotes e engines…" as if the server
            // simply had none.
            LoadFailedView(message: e) { Task { await vm.load() } }
        } else if vm.packages.isEmpty {
            EmptyStateView(icon: "fork.knife", title: "Cookbook",
                           message: "Pacotes e engines para servir modelos.")
        } else {
            let groups = vm.grouped
            List {
                if let n = vm.note {
                    Text(n).font(.ody(.footnote)).foregroundStyle(theme.green)
                        .listRowBackground(theme.bg)
                }
                if let e = vm.error {
                    Text(LocalizedStringKey(e)).font(.ody(.footnote)).foregroundStyle(theme.danger)
                        .listRowBackground(theme.bg)
                }
                ForEach(groups, id: \.category) { group in
                    Section {
                        ForEach(group.items) { pkg in
                            row(pkg)
                                .listRowBackground(theme.panel)
                                .rowSeparatorInset(32 + Spacing.iconGap)
                        }
                    } header: {
                        Text(group.category)
                            .font(.ody(.footnote, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                            .textCase(nil)
                    }
                }
            }
            // The system's grouped cards, one per category: a flat list read
            // as one long column of identical rows.
            .groupedCards()
            .scrollContentBackground(.hidden)
            .readableColumn()
            .listBottomBreathing()
        }
    }

    private func row(_ pkg: CookbookPackage) -> some View {
        HStack(spacing: Spacing.iconGap) {
            Image(systemName: "shippingbox")
                .font(.ody(.body))
                .foregroundStyle(theme.accentText)
                .frame(width: 32, height: 32)
                .background(theme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(pkg.name).font(.ody(.body)).foregroundStyle(theme.fg)
                if !pkg.desc.isEmpty {
                    Text(pkg.desc).font(.ody(.footnote))
                        .foregroundStyle(theme.secondaryText).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            status(pkg)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func status(_ pkg: CookbookPackage) -> some View {
        if pkg.installed {
            Label { Text("instalado") } icon: { Image(systemName: "checkmark") }
                .font(.ody(.subheadline, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(theme.green)
        } else if vm.installing.contains(pkg.id) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("instalando…").font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        } else if pkg.canInstall {
            Button { Task { await vm.install(pkg) } } label: {
                Text("Instalar").font(.ody(.subheadline, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .foregroundStyle(theme.accentText)
                    .background(theme.accent.opacity(0.22), in: Capsule())
                    .frame(minHeight: Spacing.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private extension View {
    /// Inset grouped cards on iOS; macOS has no such style and keeps the
    /// plain list it had.
    @ViewBuilder func groupedCards() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.plain)
        #endif
    }
}
