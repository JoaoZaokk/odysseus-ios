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
        catch is CancellationError {}
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
        do { try await api.pinMemory(m.id); await load() }
        catch { self.error = msg(error) }
    }

    func audit() async {
        auditing = true; defer { auditing = false }
        do {
            let r = try await api.auditMemories()
            await load()
            auditMessage = r.removed == 0
                ? "Memórias já estão organizadas — nada a remover."
                : "Organizado: \(r.removed) removida(s) (\(r.before) → \(r.after))."
        } catch {
            auditMessage = "Falha ao organizar: \(msg(error))"
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
    @State private var newCategory = "fact"

    init(app: AppState) { _vm = StateObject(wrappedValue: BrainViewModel(api: app.api)) }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            content
        }
        .odySearchable(text: $vm.search, prompt: "Buscar memórias")
        .screenChrome(title: "Brain") {
        } trailing: {
            Button { showAdd = true } label: { Image(systemName: "plus") }
            Button { Task { await vm.audit() } } label: {
                if vm.auditing { ProgressView() } else { Image(systemName: "wand.and.sparkles") }
            }
            .disabled(vm.auditing)
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .alert("Nova memória", isPresented: $showAdd) {
            TextField("O que o assistente deve lembrar?", text: $newText)
            TextField("Categoria", text: $newCategory)
            Button("Adicionar") {
                Task { await vm.add(newText, category: newCategory); newText = "" }
            }
            Button("Cancelar", role: .cancel) { newText = "" }
        }
        .alert("Organizar memórias", isPresented: Binding(
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
        } else if vm.memories.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                categoryBar
                List {
                    ForEach(vm.filtered) { m in
                        memoryRow(m).listRowBackground(theme.bg)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private func chip(_ label: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label)
                .font(.ody(size: 12, design: .monospaced))
                .foregroundStyle(active ? .white : theme.secondaryText)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(active ? theme.accent : theme.panel, in: Capsule())
        }
    }

    private func memoryRow(_ m: Memory) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: m.pinned ? "pin.fill" : "circle.fill")
                .font(m.pinned ? .caption : .ody(size: 6))
                .foregroundStyle(m.pinned ? theme.accent : theme.secondaryText)
                .frame(width: 16)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(m.text)
                    .font(.ody(.subheadline, design: .monospaced))
                    .foregroundStyle(theme.fg)
                Text(m.category)
                    .font(.ody(size: 10, design: .monospaced))
                    .foregroundStyle(theme.green)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { Task { await vm.delete(m) } } label: {
                Label("Apagar", systemImage: "trash")
            }
            Button { Task { await vm.togglePin(m) } } label: {
                Label(m.pinned ? "Desafixar" : "Fixar", systemImage: "pin")
            }.tint(theme.accent)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain").font(.ody(size: 44)).foregroundStyle(theme.accent)
            Text("Sem memórias ainda")
                .font(.ody(.headline, design: .monospaced)).foregroundStyle(theme.fg)
            Text("O que o assistente lembrar de você aparece aqui.")
                .font(.ody(.footnote, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
