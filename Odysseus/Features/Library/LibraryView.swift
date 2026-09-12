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
    /// The server extracts, chunks and embeds the file *inside* this request
    /// (routes/personal_routes.py) — minutes for a real PDF — so it goes through
    /// `streamSession`, not the 30-second default (the chat upload already does).
    /// It always answers 200 `{success: true, indexed_count, failed_count}`;
    /// a file refused for size or with no extractable text is only visible in
    /// the counts. From the second upload on the listing is stale until
    /// `/api/personal/reload` runs, so that is called best-effort afterwards.
    func uploadPersonal(_ data: Data, filename: String) async throws {
        var req = request("/api/personal/upload", method: "POST")
        var form = MultipartForm()
        form.append(file: "files", filename: filename, mime: "application/octet-stream", fileData: data)
        req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = form.finalizedData
        let body = try await send(req, via: streamSession)
        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            let indexed = (obj["indexed_count"] as? Int) ?? 0
            let failed = (obj["failed_count"] as? Int) ?? 0
            if failed > 0 && indexed == 0 {
                throw APIError.transport(L("O servidor recusou o arquivo (sem texto extraível ou acima do limite)."))
            }
        }
        _ = try? await send(request("/api/personal/reload", method: "POST"), via: streamSession)
    }
    func deletePersonal(_ filepath: String) async throws {
        // `.urlQueryAllowed` permits `&`, so a name containing one splits into extra
        // query parameters and the server deletes nothing while answering 200.
        _ = try await send(request("/api/personal/file?filepath=\(encQuery(filepath))", method: "DELETE"), via: streamSession)
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
        catch let e where e.isCancellation {}
        catch { self.error = SettingsUI.msg(error) }
    }
    func upload(_ url: URL) async {
        uploading = true; defer { uploading = false }
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            try await api.uploadPersonal(data, filename: url.lastPathComponent)
            await load()
        } catch { self.error = SettingsUI.msg(error) }
    }
    func delete(_ f: PersonalFile) async {
        do { try await api.deletePersonal(f.path); files.removeAll { $0.id == f.id } }
        catch { self.error = SettingsUI.msg(error) }
    }
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
        .odyRefreshable { await vm.load() }
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
        } else if vm.files.isEmpty, let e = vm.error {
            LoadFailedView(message: e) { Task { await vm.load() } }
        } else if vm.files.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "books.vertical").font(.ody(size: 44)).foregroundStyle(theme.accent)
                Text("Biblioteca vazia").font(.ody(.headline)).foregroundStyle(theme.fg)
                Text("Envie documentos (PDF, txt, md…) para o assistente consultar via RAG.")
                    .font(.ody(.footnote)).foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }.padding(40)
        } else {
            List {
                ForEach(vm.files) { f in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text").foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.displayName).font(.ody(.subheadline)).foregroundStyle(theme.fg).lineLimit(1)
                            Text(f.humanSize).font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                        }
                        Spacer()
                    }
                    .listRowBackground(theme.bg)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { Task { await vm.delete(f) } } label: { Label("Apagar", systemImage: "trash") }
                    }
                    .contextMenu {
                        Button(role: .destructive) { Task { await vm.delete(f) } } label: { Label("Apagar", systemImage: "trash") }
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
        }
    }
}
