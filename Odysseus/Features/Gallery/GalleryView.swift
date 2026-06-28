import SwiftUI

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published var images: [GalleryImage] = []
    @Published var albums: [GalleryAlbum] = []
    @Published var loading = false
    @Published var error: String?
    @Published var favoritesOnly = false

    let api: APIClient
    init(api: APIClient) { self.api = api }

    var shown: [GalleryImage] {
        favoritesOnly ? images.filter(\.favorite) : images
    }

    func load() async {
        loading = true; defer { loading = false }
        do {
            async let imgs = api.galleryLibrary()
            async let albs = api.galleryAlbums()
            images = try await imgs
            albums = (try? await albs) ?? []
            error = nil
        } catch is CancellationError {
        } catch { self.error = msg(error) }
    }

    func toggleFavorite(_ img: GalleryImage) async {
        do {
            try await api.toggleGalleryFavorite(img.id)
            if let i = images.firstIndex(where: { $0.id == img.id }) {
                images[i].favorite.toggle()
            }
        } catch { self.error = msg(error) }
    }

    func url(_ img: GalleryImage) -> URL? { api.mediaURL(img.url) }

    private func msg(_ e: Error) -> String {
        (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
    }
}

struct GalleryView: View {
    @StateObject private var vm: GalleryViewModel
    @Environment(\.theme) private var theme
    @State private var selected: GalleryImage?

    init(app: AppState) { _vm = StateObject(wrappedValue: GalleryViewModel(api: app.api)) }

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 3)]

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            content
        }
        .screenChrome(title: "Galeria") {
        } trailing: {
            Button { vm.favoritesOnly.toggle() } label: {
                Image(systemName: vm.favoritesOnly ? "heart.fill" : "heart")
                    .foregroundStyle(vm.favoritesOnly ? theme.accent : theme.fg)
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(item: $selected) { img in
            GalleryDetail(image: img, url: vm.url(img)) {
                Task { await vm.toggleFavorite(img) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.images.isEmpty && vm.loading {
            ProgressView().tint(theme.accent)
        } else if vm.shown.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(vm.shown) { img in
                        tile(img).onTapGesture { selected = img }
                    }
                }
                .padding(3)
            }
        }
    }

    private func tile(_ img: GalleryImage) -> some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: vm.url(img)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    ZStack { theme.panel; Image(systemName: "photo").foregroundStyle(theme.secondaryText) }
                default:
                    ZStack { theme.panel; ProgressView().tint(theme.accent) }
                }
            }
            .frame(minHeight: 110).frame(maxWidth: .infinity).frame(height: 110)
            .clipped()

            if img.isVideo {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.white).shadow(radius: 2)
                    .padding(4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            if img.favorite {
                Image(systemName: "heart.fill")
                    .font(.caption2).foregroundStyle(.white).shadow(radius: 2).padding(5)
            }
        }
        .background(theme.panel)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled").font(.ody(size: 44)).foregroundStyle(theme.accent)
            Text(LocalizedStringKey(vm.favoritesOnly ? "Sem favoritos" : "Galeria vazia"))
                .font(.ody(.headline, design: .monospaced)).foregroundStyle(theme.fg)
            Text("Imagens geradas e enviadas aparecem aqui.")
                .font(.ody(.footnote, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(40)
    }
}

struct GalleryDetail: View {
    let image: GalleryImage
    let url: URL?
    let onFavorite: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().aspectRatio(contentMode: .fit)
                            case .failure: Image(systemName: "photo").font(.largeTitle).foregroundStyle(.gray)
                            default: ProgressView().tint(.white).frame(height: 240)
                            }
                        }
                        if !image.prompt.isEmpty {
                            Text(image.prompt)
                                .font(.ody(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 16)
                                .textSelection(.enabled)
                        }
                        if let m = image.model {
                            Text(m).font(.ody(size: 11, design: .monospaced)).foregroundStyle(.gray)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fechar") { dismiss() } }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onFavorite()
                    } label: {
                        Image(systemName: image.favorite ? "heart.fill" : "heart")
                            .foregroundStyle(theme.accent)
                    }
                }
            }
        }
        .tint(theme.accent)
    }
}
