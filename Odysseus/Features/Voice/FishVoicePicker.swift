import SwiftUI

/// Browses Fish Audio's voice library so a voice can be chosen by name instead
/// of by pasting a `reference_id`. Language matters here beyond taste: asking
/// for Portuguese without filtering hands you a European voice.
struct FishVoicePicker: View {
    /// Called with the chosen voice's id and title.
    let onPick: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var voices: [VoiceEndpoint.FishVoice] = []
    @State private var search = ""
    @State private var language = ""
    @State private var mine = false
    @State private var loading = false
    @State private var error: String?

    /// Fish tags voices with plain language codes; these are the ones the app
    /// itself speaks, plus "all" to stop filtering.
    private let languages = [("", L("Todos")), ("pt", "Português"), ("en", "English"),
                             ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"),
                             ("it", "Italiano"), ("ja", "日本語"), ("zh", "中文")]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(L("Idioma"), selection: $language) {
                        ForEach(languages, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Toggle(L("Só minhas vozes"), isOn: $mine)
                }

                if loading {
                    HStack { ProgressView(); Text("Carregando…") }
                } else if let error {
                    Text(LocalizedStringKey(error)).font(.footnote).foregroundStyle(theme.accent)
                } else if voices.isEmpty {
                    Text("Nenhuma voz encontrada.").foregroundStyle(.secondary)
                }

                ForEach(voices) { v in
                    Button {
                        onPick(v.id, v.title)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.title).foregroundStyle(.primary)
                            let detail = (v.languages + [v.author]).filter { !$0.isEmpty }
                            if !detail.isEmpty {
                                Text(detail.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("Escolher voz"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancelar")) { dismiss() }
                }
            }
            .searchable(text: $search, prompt: Text(L("Buscar voz")))
            // Re-queries on every filter change; the search text is debounced by
            // .task's own cancellation when it changes again quickly.
            .task(id: "\(search)|\(language)|\(mine)") { await load() }
        }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            voices = try await VoiceEndpoint.fishVoices(search: search,
                                                        language: language.isEmpty ? nil : language,
                                                        mine: mine)
        } catch {
            // Superseded by a newer query — leave the list as it is. `catch is
            // CancellationError` looks like it does this but never matches:
            // URLSession raises URLError.cancelled, so every keystroke used to
            // blank the list and flash a spurious error.
            guard !error.isCancellation else { return }
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            voices = []
        }
    }
}
