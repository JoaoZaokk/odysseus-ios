import SwiftUI
import UniformTypeIdentifiers

// MARK: - Models

struct PersonalFile: Decodable, Identifiable, Hashable, Sendable {
    var name: String
    var path: String
    var size: Int
    var id: String { path.isEmpty ? name : path }

    enum CodingKeys: String, CodingKey { case name, path, size }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        path = (try? c.decode(String.self, forKey: .path)) ?? name
        size = (try? c.decode(Int.self, forKey: .size)) ?? 0
    }

    var displayName: String { name.split(separator: "/").last.map(String.init) ?? name }
    var humanSize: String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: Int64(size))
    }
}

struct PersonalListing: Decodable {
    var files: [PersonalFile]
    var directories: [PersonalFile]
    enum CodingKeys: String, CodingKey { case files, directories }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        files = (try? c.decode([PersonalFile].self, forKey: .files)) ?? []
        directories = (try? c.decode([PersonalFile].self, forKey: .directories)) ?? []
    }
}

// MARK: - API

extension APIClient {
    func personalFiles() async throws -> PersonalListing {
        try decode(PersonalListing.self, try await send(request("/api/personal")))
    }
    func uploadPersonal(_ data: Data, filename: String) async throws {
        var req = request("/api/personal/upload", method: "POST")
        var form = MultipartForm()
        form.append(file: "files", filename: filename, mime: "application/octet-stream", fileData: data)
        req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = form.finalizedData
        _ = try await send(req)
    }
    func deletePersonal(_ filepath: String) async throws {
        let enc = filepath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filepath
        _ = try await send(request("/api/personal/file?filepath=\(enc)", method: "DELETE"))
    }
}

// MARK: - View

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var files: [PersonalFile] = []
    @Published var loading = false
    @Published var uploading = false
    @Published var error: String?

    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func load() async {
        loading = true; defer { loading = false }
        do { files = try await api.personalFiles().files; error = nil }
        catch is CancellationError {}
        catch { self.error = msg(error) }
    }
    func upload(_ url: URL) async {
        uploading = true; defer { uploading = false }
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            try await api.uploadPersonal(data, filename: url.lastPathComponent)
            await load()
        } catch { self.error = msg(error) }
    }
    func delete(_ f: PersonalFile) async {
        do { try await api.deletePersonal(f.path); files.removeAll { $0.id == f.id } }
        catch { self.error = msg(error) }
    }
    private func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? e.localizedDescription }
}

struct LibraryView: View {
    @StateObject private var vm: LibraryViewModel
    @Environment(\.theme) private var theme
    @State private var importing = false
    init(app: AppState) { _vm = StateObject(wrappedValue: LibraryViewModel(api: app.api)) }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            content
        }
        .screenChrome(title: "Library") {
        } trailing: {
            Button { importing = true } label: {
                if vm.uploading { ProgressView() } else { Image(systemName: "arrow.up.doc") }
            }.disabled(vm.uploading)
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await vm.upload(url) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.files.isEmpty && vm.loading {
            ProgressView().tint(theme.accent)
        } else if vm.files.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "books.vertical").font(.ody(size: 44)).foregroundStyle(theme.accent)
                Text("Biblioteca vazia").font(.ody(.headline, design: .monospaced)).foregroundStyle(theme.fg)
                Text("Envie documentos (PDF, txt, md…) para o assistente consultar via RAG.")
                    .font(.ody(.footnote, design: .monospaced)).foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }.padding(40)
        } else {
            List {
                ForEach(vm.files) { f in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text").foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.displayName).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg).lineLimit(1)
                            Text(f.humanSize).font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                        }
                        Spacer()
                    }
                    .listRowBackground(theme.bg)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { Task { await vm.delete(f) } } label: { Label("Apagar", systemImage: "trash") }
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
        }
    }
}
