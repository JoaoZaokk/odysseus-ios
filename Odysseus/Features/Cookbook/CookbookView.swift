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
    /// (matches the web Cookbook: POST /api/model/serve `{repo_id, cmd}`). The
    /// server runs it in the background; reload packages later to see the status.
    func installCookbookPackage(_ pkg: CookbookPackage) async throws {
        let pip = pkg.pip ?? ""
        guard !pip.isEmpty else { throw APIError.transport("Pacote sem alvo pip.") }
        struct Body: Encodable { let repo_id: String; let cmd: String }
        let cmd = "python3 -m pip install --user --break-system-packages \"\(pip)\""
        let req = try jsonRequest("/api/model/serve", method: "POST",
                                  body: Body(repo_id: pip, cmd: cmd))
        _ = try await send(req)
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
            note = "Instalação de \(pkg.name) iniciada no servidor — pode levar alguns minutos."
            // Give the background job a head start, then refresh status.
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await load()
        } catch {
            self.error = "Falha ao instalar \(pkg.name): \(msg(error))"
        }
    }

    var grouped: [(category: String, items: [CookbookPackage])] {
        let buckets = Dictionary(grouping: packages) { $0.category }
        return buckets.map { (category: $0.key, items: $0.value) }.sorted { $0.category < $1.category }
    }

    func load() async {
        loading = true; defer { loading = false }
        do { packages = try await api.cookbookPackages(); error = nil }
        catch is CancellationError {}
        catch { self.error = msg(error) }
    }
    private func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? e.localizedDescription }
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
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.packages.isEmpty && vm.loading {
            ProgressView().tint(theme.accent)
        } else if vm.packages.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "fork.knife").font(.ody(size: 44)).foregroundStyle(theme.accent)
                Text("Cookbook").font(.ody(.headline, design: .monospaced)).foregroundStyle(theme.fg)
                Text("Pacotes e engines para servir modelos.")
                    .font(.ody(.footnote, design: .monospaced)).foregroundStyle(theme.secondaryText)
            }.padding(40)
        } else {
            List {
                if let n = vm.note {
                    Text(n).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.green)
                        .listRowBackground(theme.bg)
                }
                if let e = vm.error {
                    Text(e).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.accent)
                        .listRowBackground(theme.bg)
                }
                ForEach(vm.grouped, id: \.category) { group in
                    Section {
                        ForEach(group.items) { pkg in row(pkg).listRowBackground(theme.bg) }
                    } header: {
                        Text(group.category).font(.ody(.caption, design: .monospaced)).foregroundStyle(theme.accent)
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
        }
    }

    private func row(_ pkg: CookbookPackage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: pkg.installed ? "checkmark.circle.fill" : "shippingbox")
                .foregroundStyle(pkg.installed ? theme.green : theme.secondaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text(pkg.name).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                if !pkg.desc.isEmpty {
                    Text(pkg.desc).font(.ody(size: 10, design: .monospaced))
                        .foregroundStyle(theme.secondaryText).lineLimit(2)
                }
            }
            Spacer()
            if pkg.installed {
                Text("instalado").font(.ody(size: 9, design: .monospaced)).foregroundStyle(theme.green)
            } else if vm.installing.contains(pkg.id) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("instalando…").font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                }
            } else if pkg.canInstall {
                Button { Task { await vm.install(pkg) } } label: {
                    Text("Instalar").font(.ody(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .foregroundStyle(.white)
                        .background(theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 3)
    }
}
