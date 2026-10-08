import SwiftUI

@MainActor
final class NotesViewModel: ObservableObject {
    @Published var notes: [Note] = []
    @Published var loading = false
    @Published var error: String?
    /// Two server-side lists, not one filtered locally: `GET /api/notes` never
    /// contains an archived note, so flipping the switch has to reload.
    @Published var showArchived = false {
        didSet { if oldValue != showArchived { Task { await load() } } }
    }

    private let api: APIClient
    init(api: APIClient) { self.api = api }

    /// The server already returned the right list (`?archived=`); filtering
    /// again locally could only hide rows whose `archived` field is absent.
    var visible: [Note] {
        notes.sorted { ($0.pinned ? 1 : 0) > ($1.pinned ? 1 : 0) }
    }

    func load() async {
        loading = true; defer { loading = false }
        do { notes = try await api.notes(archived: showArchived); error = nil }
        catch let e where e.isCancellation {}
        catch { self.error = msg(error) }
    }

    func save(id: String?, title: String, content: String) async {
        // nil, not false: the field is omitted from the body, so the server keeps
        // whatever the note already had. Sending `false` unarchived it on every edit.
        let payload = NotePayload(title: title, content: content, archived: nil, pinned: nil)
        do {
            if let id { try await api.updateNote(id, payload) }
            else { try await api.createNote(payload) }
            await load()
        } catch { self.error = msg(error) }
    }

    func toggleArchive(_ n: Note) async {
        do { try await api.patchNote(n.id, fields: ["archived": !n.archived]); await load() }
        catch { self.error = msg(error) }
    }

    func delete(_ n: Note) async {
        do { try await api.deleteNote(n.id); notes.removeAll { $0.id == n.id } }
        catch { self.error = msg(error) }
    }

    private func msg(_ e: Error) -> String {
        (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
    }
}

struct NotesView: View {
    @StateObject private var vm: NotesViewModel
    @Environment(\.theme) private var theme
    @State private var editing: Note?

    init(app: AppState) { _vm = StateObject(wrappedValue: NotesViewModel(api: app.api)) }

    // `.top`: a grid row centres its cells vertically by default, so two notes
    // of different heights side by side started at different heights (196 and 208).
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)]

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            content
        }
        .screenChrome(title: vm.showArchived ? "Notes · arquivadas" : "Notes") {
        } trailing: {
            Button { vm.showArchived.toggle() } label: {
                Image(systemName: vm.showArchived ? "tray.full" : "archivebox")
            }
            Button { editing = Note() } label: { Image(systemName: "plus") }
        }
        .task { await vm.load() }
        .odyRefreshable { await vm.load() }
        .sheet(item: $editing) { note in
            NoteEditor(note: note) { title, content in
                Task { await vm.save(id: note.id.isEmpty ? nil : note.id, title: title, content: content) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.notes.isEmpty && vm.loading {
            ProgressView().tint(theme.accent)
        } else if vm.notes.isEmpty, let e = vm.error {
            LoadFailedView(message: e) { Task { await vm.load() } }
        } else if vm.visible.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(vm.visible) { note in
                        noteCard(note).onTapGesture { editing = note }
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.top, 12)
                .padding(.bottom, Spacing.bottomBreathing)
            }
        }
    }

    private func noteCard(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !note.title.isEmpty {
                    Text(note.title)
                        .font(.ody(.subheadline).weight(.semibold))
                        .foregroundStyle(theme.fg).lineLimit(2)
                }
                Spacer(minLength: 0)
                if note.pinned {
                    Image(systemName: "pin.fill").font(.ody(size: 11)).foregroundStyle(theme.accent)
                        .accessibilityLabel(Text("Fixada"))
                }
            }
            Text(note.content)
                .font(.ody(size: 12))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .background(theme.aiBubble, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border.opacity(0.4), lineWidth: 1))
        .contextMenu {
            Button { Task { await vm.toggleArchive(note) } } label: {
                Label(note.archived ? "Desarquivar" : "Arquivar", systemImage: "archivebox")
            }
            Button(role: .destructive) { Task { await vm.delete(note) } } label: {
                Label("Apagar", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(icon: "note.text",
                       title: vm.showArchived ? "Nada arquivado" : "Sem notas ainda",
                       message: vm.showArchived ? nil : "Toque em + para criar sua primeira nota.")
    }
}

struct NoteEditor: View {
    let note: Note
    let onSave: (String, String) -> Void
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""

    var body: some View {
        NavigationStack {
            ZStack {
                theme.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    TextField("Título", text: $title)
                        .font(.ody(.title3).weight(.semibold))
                        .foregroundStyle(theme.fg)
                        .padding(.horizontal, 16).padding(.top, 16)
                    Divider().overlay(theme.border).padding(.vertical, 8)
                    TextEditor(text: $content)
                        .font(.ody(.body))
                        .foregroundStyle(theme.fg)
                        .scrollContentBackground(.hidden)
                        .background(theme.bg)
                        .padding(.horizontal, 12)
                }
            }
            .odyNavTitle(note.id.isEmpty ? "Nova nota" : "Editar nota")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    BarButton("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    BarButton("Salvar") { onSave(title, content); dismiss() }
                        .disabled(title.isEmpty && content.isEmpty)
                }
            }
        }
        .tint(theme.accent)
        .onAppear { title = note.title; content = note.content }
    }
}
