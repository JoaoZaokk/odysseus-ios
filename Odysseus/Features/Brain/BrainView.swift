import SwiftUI

@MainActor
final class BrainViewModel: ObservableObject {
    @Published var memories: [Memory] = []
    @Published var loading = false
    @Published var error: String?
    @Published var search = ""
    @Published var activeCategory: String?
    @Published var auditing = false
    @Published var auditMessage: String?

    private let api: APIClient
    init(api: APIClient) { self.api = api }

    var categories: [String] {
        Array(Set(memories.map(\.category))).sorted()
    }

    var filtered: [Memory] {
        memories
            .filter { activeCategory == nil || $0.category == activeCategory }
            .filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) }
            .sorted { ($0.pinned ? 1 : 0) > ($1.pinned ? 1 : 0) }
    }

    func load() async {
        loading = true; defer { loading = false }
        do { memories = try await api.memories(); error = nil }
        catch let e where e.isCancellation {}
        catch { self.error = msg(error) }
    }

    func add(_ text: String, category: String?) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        do { try await api.addMemory(text: t, category: category); await load() }
        catch { self.error = msg(error) }
    }

    func delete(_ m: Memory) async {
        do { try await api.deleteMemory(m.id); memories.removeAll { $0.id == m.id } }
        catch { self.error = msg(error) }
    }

    func togglePin(_ m: Memory) async {
        do { try await api.pinMemory(m.id, pinned: !m.pinned); await load() }
        catch { self.error = msg(error) }
    }

    func audit() async {
        auditing = true; defer { auditing = false }
        do {
            let r = try await api.auditMemories()
            await load()
            auditMessage = r.removed == 0
                ? L("Memórias já estão organizadas — nada a remover.")
                : L("Organizado: %lld → %lld · removidas: %lld", r.before, r.after, r.removed)
        } catch {
            auditMessage = L("Falha ao organizar: %@", msg(error))
        }
    }

    private func msg(_ e: Error) -> String {
        (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
    }
}

struct BrainView: View {
    @StateObject private var vm: BrainViewModel
    @Environment(\.theme) private var theme
    @State private var showAdd = false
    @State private var newText = ""
    /// Empty shows the "Categoria" placeholder; an empty category is sent as
    /// "fact", the server's default, as the pre-filled English word used to be.
    @State private var newCategory = ""

    init(app: AppState) { _vm = StateObject(wrappedValue: BrainViewModel(api: app.api)) }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            content
        }
        .screenChrome(title: "Brain") {
        } trailing: {
            Button { showAdd = true } label: { Image(systemName: "plus") }
            Button { Task { await vm.audit() } } label: {
                if vm.auditing { ProgressView() } else { Image(systemName: "wand.and.stars") }
            }
            .disabled(vm.auditing)
        }
        .task {
            await vm.load()
            #if DEBUG
            if ScreenshotRoute.matches("memory") { showAdd = true }
            #endif
        }
        .odyRefreshable { await vm.load() }
        .odyAlert("Nova memória", isPresented: $showAdd) {
            TextField("O que o assistente deve lembrar?", text: $newText)
            TextField("Categoria", text: $newCategory)
            Button("Adicionar") {
                let category = newCategory.trimmingCharacters(in: .whitespaces)
                Task { await vm.add(newText, category: category.isEmpty ? "fact" : category); newText = "" }
            }
            Button("Cancelar", role: .cancel) { newText = "" }
        }
        .odyAlert("Organizar memórias", isPresented: Binding(
            get: { vm.auditMessage != nil },
            set: { if !$0 { vm.auditMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.auditMessage = nil }
        } message: {
            Text(vm.auditMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.memories.isEmpty && vm.loading {
            ProgressView().tint(theme.accent)
        } else if vm.memories.isEmpty, let e = vm.error {
            LoadFailedView(message: e) { Task { await vm.load() } }
        } else if vm.memories.isEmpty {
            emptyState
        } else {
            // The search sits on top, in the content, like the conversation
            // list's: `.searchable` floats at the bottom edge on iOS 26, in
            // the system sans, away from the list it filters.
            let shown = vm.filtered
            VStack(spacing: 0) {
                OdySearchField(text: $vm.search, prompt: "Buscar memórias")
                categoryBar
                List {
                    ForEach(shown) { m in
                        memoryRow(m)
                            .listRowBackground(theme.bg)
                            .gutterRowInsets(vertical: 8)
                            .rowSeparatorInset()
                            .edgeSeparators(first: m.id == shown.first?.id, last: m.id == shown.last?.id)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listBottomBreathing()
            }
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Tudo", active: vm.activeCategory == nil) { vm.activeCategory = nil }
                ForEach(vm.categories, id: \.self) { cat in
                    chip(cat, active: vm.activeCategory == cat) { vm.activeCategory = cat }
                }
            }
            .padding(.leading, Spacing.gutter)
            .padding(.trailing, Spacing.gutter + 36)
            .padding(.vertical, 2)
        }
        .trailingFade()
    }

    private func chip(_ label: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(LocalizedStringKey(label))
                .font(.ody(size: 12))
                .foregroundStyle(active ? .white : theme.secondaryText)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(active ? theme.accent : theme.panel, in: Capsule())
                // Looks 28 tall, answers to 44.
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func memoryRow(_ m: Memory) -> some View {
        HStack(alignment: .top, spacing: Spacing.iconGap) {
            // Pin and bullet share the 24 column, so the text starts on the
            // same edge whether the memory is pinned or not.
            Image(systemName: m.pinned ? "pin.fill" : "circle.fill")
                .font(.ody(size: m.pinned ? 12 : 6))
                .foregroundStyle(m.pinned ? theme.accent : theme.secondaryText)
                .frame(width: Spacing.leadingColumn, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(m.text)
                    .font(.ody(.subheadline))
                    .foregroundStyle(theme.fg)
                Text(m.category)
                    .font(.ody(size: 11))
                    .foregroundStyle(theme.green)
            }
            Spacer()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { Task { await vm.delete(m) } } label: {
                Label("Apagar", systemImage: "trash")
            }
            Button { Task { await vm.togglePin(m) } } label: {
                Label(LocalizedStringKey(m.pinned ? "Desafixar" : "Fixar"), systemImage: "pin")
            }.tint(theme.accent)
        }
        // A swipe does not exist on macOS (and is undiscoverable on iPad with a
        // pointer): the same actions on right-click / long press.
        .contextMenu {
            Button { Task { await vm.togglePin(m) } } label: {
                Label(LocalizedStringKey(m.pinned ? "Desafixar" : "Fixar"), systemImage: "pin")
            }
            Button(role: .destructive) { Task { await vm.delete(m) } } label: { Label("Apagar", systemImage: "trash") }
        }
    }

    private var emptyState: some View {
        EmptyStateView(icon: "brain", title: "Sem memórias ainda",
                       message: "O que o assistente lembrar de você aparece aqui.")
    }
}
