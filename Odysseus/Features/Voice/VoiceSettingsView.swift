import SwiftUI

struct VoiceSettingsView: View {
    @Environment(\.theme) private var theme
    @StateObject private var downloads = ModelDownloadManager.shared
    @ObservedObject private var speech = SpeechManager.shared
    // Observed so the neural row re-labels the moment the app language changes.
    @ObservedObject private var uiLanguage = LocalizationManager.shared
    @ObservedObject private var neural = NeuralVoiceStore.shared
    /// Non-nil while the delete confirmation is up. Freeing ~550 MB is cheap to
    /// undo (re-download) but slow, so it asks first.
    @State private var pendingDelete: NeuralVoiceStore.Pack?
    @State private var customURL = ""
    @State private var addingModel = false

    // Key and default come from the enums, so this screen — the one place that
    // WRITES the engine — cannot disagree with the places that read it.
    @AppStorage(STTEngine.key) private var sttEngine = STTEngine.native.rawValue
    @AppStorage("voice.stt.model") private var sttModelID = ""
    @AppStorage(TTSEngine.key) private var ttsEngine = TTSEngine.native.rawValue
    @AppStorage("voice.tts.pocketVoice") private var pocketVoice = "alba"
    @AppStorage("voice.stt.onDeviceOnly") private var sttOnDeviceOnly = false
    @AppStorage(SpeechLanguage.key) private var sttLanguage = SpeechLanguage.followApp
    @AppStorage("voice.tts.streaming") private var ttsStreaming = true
    @AppStorage("voice.bargein.enabled") private var bargeEnabled = true
    @AppStorage("voice.bargein.sensitivity") private var bargeSensitivity = 0.5
    @State private var langFilter = "all"

    private var lang: VoiceLang? { VoiceLang(rawValue: langFilter) }

    /// The engines are *persisted* as raw strings — that is what the pickers
    /// bind to — but every question this screen asks about them is asked of the
    /// enum, so the list of engines exists in one place instead of once per
    /// screen that reads it.
    private var stt: STTEngine { STTEngine(rawValue: sttEngine) ?? .native }
    private var tts: TTSEngine { TTSEngine(rawValue: ttsEngine) ?? .native }

    var body: some View {
        List {
            Section {
                Picker("Reconhecimento (STT)", selection: $sttEngine) {
                    ForEach(STTEngine.allCases) { engine in
                        Text(verbatim: engine.label).tag(engine.rawValue)
                    }
                }
                if stt == .endpoint {
                    VoiceEndpointFields(kind: .stt)
                    STTTestRow()
                }
                if stt == .model {
                    LabeledContent("Modelo ativo", value: modelName(sttModelID) ?? L("nenhum"))
                }
                if stt == .native {
                    Toggle("Processar só no aparelho", isOn: $sttOnDeviceOnly)
                }
                Picker("Idioma da fala", selection: $sttLanguage) {
                    Text(verbatim: L("Seguir o app (%@)", uiLanguage.active.nativeName))
                        .tag(SpeechLanguage.followApp)
                    // Offered even under the native engine, where it degrades to
                    // the app language: dropping the row when the engine changes
                    // would leave an already-chosen "detect" selecting nothing,
                    // and the footer says what it does instead.
                    Text("Detectar automaticamente").tag(SpeechLanguage.auto)
                    // Native names, so someone hunting for their own language
                    // can find it without reading the current one.
                    ForEach(AppLanguage.allCases) { l in
                        Text(verbatim: l.nativeName).tag(l.rawValue)
                    }
                }
            } header: { Text("Voz → Texto") } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nativo = transcrição ao vivo enquanto você fala (tipo Claude/Gemini). \"Modelo\" = Whisper offline no aparelho. \"Servidor\" = o Whisper do seu Odysseus (envia o áudio e transcreve no fim).")
                    Text("\"Endpoint próprio\" = qualquer serviço compatível com a API de áudio da OpenAI (POST /audio/transcriptions). Nada é baixado no aparelho.")
                    if sttLanguage == SpeechLanguage.followApp {
                        Text("A voz nativa e o reconhecimento nativo seguem o idioma do app (Ajustes › Idioma).")
                    } else {
                        Text("A voz nativa segue o idioma do app. O reconhecimento usa o idioma escolhido acima; detectar automaticamente erra mais em áudio curto ou com ruído, e o reconhecimento nativo do iOS não detecta nada — nele vale sempre o idioma do app.")
                    }
                    if stt == .native {
                        Text("Processar só no aparelho não envia áudio à Apple, mas o modelo offline erra mais palavras. Deixe desligado se a transcrição estiver ruim.")
                    }
                }
            }

            Section {
                Picker("Voz da IA (TTS)", selection: $ttsEngine) {
                    Text("Nativo iOS").tag(TTSEngine.native.rawValue)
                    // Names the pack that will actually be used, so picking
                    // "Neural" in a language with no pack isn't a surprise.
                    Text(verbatim: speech.neuralAvailableForCurrentLanguage
                         ? L("Neural (%@)", uiLanguage.active.nativeName)
                         : L("Neural (indisponível)")).tag(TTSEngine.neural.rawValue)
                    Text("Servidor").tag(TTSEngine.server.rawValue)
                    Text("Endpoint próprio").tag(TTSEngine.endpoint.rawValue)
                }
                if tts == .endpoint {
                    VoiceEndpointFields(kind: .tts)
                    Toggle("Áudio em streaming", isOn: $ttsStreaming)
                    // `toggleTest`, not `toggle`: the test has to take whichever
                    // path the conversation itself would take (streaming
                    // included), or it passes green against an endpoint the
                    // conversation then cannot use — see `SpeechManager.toggleTest`.
                    testVoiceButton(L("Olá! É assim que a voz vai soar.")) {
                        speech.toggleTest($0, id: SpeechManager.testID)
                    }
                    speechErrorLine
                }
                if tts == .server {
                    // No voice or model picker: /api/tts/synthesize takes only
                    // the text. Report what the server is set to instead, so an
                    // unexpected voice has a visible explanation.
                    if let s = speech.serverStats {
                        LabeledContent("Serviço", value: s.available ? L("disponível") : L("indisponível"))
                        if !s.summary.isEmpty {
                            LabeledContent("Configuração do servidor", value: s.summary)
                        }
                    }
                    testVoiceButton(L("Olá! Esta é a voz do servidor.")) {
                        speech.toggle($0, id: SpeechManager.testID)
                    }
                    speechErrorLine
                }
                if tts == .neural {
                    // The 26 voice names are identical in every pack, so the
                    // picker never has to change with the language.
                    Picker("Voz", selection: $pocketVoice) {
                        ForEach(PocketVoices.all, id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(!speech.neuralAvailableForCurrentLanguage)
                    Button { speech.prepareNeural() } label: {
                        if speech.isPreparing(SpeechManager.prepareID) {
                            HStack { ProgressView(); Text("Baixando voz neural…") }
                        } else if speech.neuralReady {
                            Label("Voz neural pronta", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(theme.green)
                        } else {
                            Label("Baixar voz neural (~550 MB)", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(speech.isPreparing(SpeechManager.prepareID) || speech.neuralReady
                              || !speech.neuralAvailableForCurrentLanguage)
                    speechErrorLine
                }
            } header: { Text("Texto → Voz") } footer: {
                if tts == .endpoint {
                    Text("Áudio em streaming toca a primeira frase enquanto ela ainda está sendo gerada, em vez de esperar o arquivo inteiro. Vale só no modo conversa (a tela de voz); as frases seguintes já são preparadas enquanto a anterior toca. Desligue se o áudio picotar.")
                }
                Text("Neural = PocketTTS (CoreML/Neural Engine), bem mais natural que a voz nativa. Existe em português, inglês, espanhol, francês, alemão e italiano — segue o idioma do app e baixa ~550 MB por idioma na primeira vez. Roda só no iPhone físico (não no simulador).")
            }

            Section {
                Toggle("Interromper ao falar (barge-in)", isOn: $bargeEnabled)
                if bargeEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Sensibilidade").font(.ody(.subheadline, design: .monospaced))
                            Spacer()
                            Text(LocalizedStringKey(bargeSensitivity > 0.66 ? "Alta" : bargeSensitivity < 0.34 ? "Baixa" : "Média"))
                                .font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
                        }
                        Slider(value: $bargeSensitivity, in: 0...1)
                    }
                }
            } header: { Text("Conversa por voz") } footer: {
                Text("Enquanto a IA fala, começar a falar corta a resposta e ele te ouve. Sensibilidade alta interrompe com pouca voz (mas pode disparar sozinho com o eco); baixa exige falar mais firme.")
            }

            Section("Filtrar catálogo por idioma") {
                // Menu (not segmented): 7 options, text labels only — no flags.
                Picker("Idioma", selection: $langFilter) {
                    Text("Todos").tag("all")
                    ForEach(VoiceLang.allCases, id: \.rawValue) { l in
                        Text(l.label).tag(l.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            neuralPacksSection

            customModelSection

            modelSection(title: L("Modelos STT · Whisper"), task: .stt,
                         selectedID: sttModelID) { id in sttModelID = id; sttEngine = STTEngine.model.rawValue }

            if totalOnDisk > 0 {
                Section {
                    LabeledContent("Espaço usado",
                                   value: ByteCountFormatter.string(fromByteCount: totalOnDisk, countStyle: .file))
                }
            }
        }
        .navigationTitle("Voz e modelos")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .tint(theme.accent)
        .onAppear { downloads.refresh(); neural.refresh() }
        // Re-scan after a download finishes, so the new pack (and the freed or
        // claimed space) shows up without leaving the screen.
        .onChange(of: speech.neuralReady) { _, ready in if ready { neural.refresh() } }
        .confirmationDialog(
            Text("Apagar voz neural"),
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(deleteButtonTitle, role: .destructive) {
                if let p = pendingDelete { neural.delete(p) }
                pendingDelete = nil
            }
            Button("Cancelar", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Apagar libera o espaço; a voz é baixada de novo na próxima vez que você usar aquele idioma.")
        }
        .task(id: ttsEngine) { if tts == .server { await speech.loadServerInfo() } }
        .alert("Erro no download", isPresented: Binding(get: { downloads.error != nil }, set: { if !$0 { downloads.error = nil } })) {
            Button("OK") { downloads.error = nil }
        } message: { Text(downloads.error ?? "") }
    }

    private func modelName(_ id: String) -> String? {
        VoiceCatalog.all.first { $0.id == id }?.name
    }

    /// The endpoint and server rows differ only in the phrase and in which
    /// method speaks it; the spinner, its label and the icon are the same
    /// button, and used to be written twice.
    private func testVoiceButton(_ phrase: String, speak: @escaping (String) -> Void) -> some View {
        Button { speak(phrase) } label: {
            if speech.isPreparing(SpeechManager.testID) {
                HStack { ProgressView(); Text("Sintetizando…") }
            } else {
                Label("Testar voz", systemImage: "speaker.wave.2")
            }
        }
    }

    /// All three engine blocks report through the same `neuralError` slot: it
    /// carries whatever the *active* engine last failed with, neural or not.
    @ViewBuilder
    private var speechErrorLine: some View {
        if let e = speech.neuralError {
            Text(LocalizedStringKey(e)).font(.footnote).foregroundStyle(theme.accent)
        }
    }

    /// Install a Whisper checkpoint the app doesn't ship, by URL.
    private var customModelSection: some View {
        Section {
            TextField("https://…/ggml-modelo.bin", text: $customURL)
                .font(.ody(size: 12, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .onSubmit { addCustomModel() }
            Button { addCustomModel() } label: {
                if addingModel {
                    HStack { ProgressView(); Text("Verificando…") }
                } else {
                    Label("Baixar modelo", systemImage: "arrow.down.circle")
                }
            }
            .disabled(addingModel || customURL.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Modelo próprio")
        } footer: {
            Text("Aceita só link https de um modelo Whisper no formato ggml (.bin) — o mesmo do catálogo abaixo. Cole o link do arquivo; o link da página do Hugging Face é convertido sozinho.")
                .font(.ody(size: 11, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func addCustomModel() {
        let text = customURL
        guard !addingModel, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        addingModel = true
        Task {
            do {
                try await downloads.addCustomModel(from: text)
                customURL = ""
            } catch {
                downloads.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            addingModel = false
        }
    }

    /// Names what's being freed, so the destructive button isn't a bare "Delete".
    private var deleteButtonTitle: String {
        guard let p = pendingDelete else { return L("Apagar") }
        return L("Apagar %@ (%@)", NeuralVoiceStore.label(p.language),
                 ByteCountFormatter.string(fromByteCount: p.bytes, countStyle: .file))
    }

    /// Whisper models + the PocketTTS packs — everything this screen downloaded.
    private var totalOnDisk: Int64 {
        downloads.totalInstalledBytes() + neural.totalBytes
    }

    /// Downloaded neural voice packs, with what each costs and a way out.
    /// Only rendered once something is actually on disk, so the common case
    /// (never touched the neural engine) shows nothing.
    @ViewBuilder
    private var neuralPacksSection: some View {
        if !neural.packs.isEmpty {
            Section {
                ForEach(neural.packs) { pack in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: NeuralVoiceStore.label(pack.language))
                                .font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                            Text(verbatim: ByteCountFormatter.string(fromByteCount: pack.bytes, countStyle: .file))
                                .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                        }
                        Spacer()
                        Button(role: .destructive) { pendingDelete = pack } label: {
                            Image(systemName: "trash").font(.ody(size: 16))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Apagar voz neural"))
                    }
                    .listRowBackground(theme.bg)
                }
            } header: {
                Text("Vozes neurais baixadas")
            } footer: {
                Text("Apagar libera o espaço; a voz é baixada de novo na próxima vez que você usar aquele idioma.")
                    .font(.ody(size: 11, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    /// ⚡ = Core ML / Neural Engine acceleration for a Whisper model.
    @ViewBuilder
    private func coreMLControl(_ model: VoiceModel) -> some View {
        if let p = downloads.coreMLProgress(model) {
            HStack(spacing: 4) {
                Text("\(Int(p * 100))%").font(.ody(size: 9, design: .monospaced)).foregroundStyle(theme.secondaryText)
                Button { downloads.cancelCoreML(model) } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Cancelar download"))
            }
        } else if downloads.hasCoreML(model) {
            Button { downloads.deleteCoreML(model) } label: {
                Image(systemName: "bolt.fill").font(.ody(size: 18)).foregroundStyle(theme.green)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Remover aceleração Core ML"))
        } else {
            Button { downloads.downloadCoreML(model) } label: {
                Image(systemName: "bolt").font(.ody(size: 18)).foregroundStyle(theme.secondaryText)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Ativar aceleração Core ML"))
        }
    }

    @ViewBuilder
    private func modelSection(title: String, task: VoiceTask, selectedID: String, select: @escaping (String) -> Void) -> some View {
        let models = VoiceCatalog.filtered(task: task, lang: lang)
        ForEach(VoiceModel.Bucket.allCases, id: \.rawValue) { bucket in
            let items = models.filter { $0.bucket == bucket }
            if !items.isEmpty {
                Section {
                    ForEach(items) { model in
                        modelRow(model, selected: selectedID == model.id, select: select)
                    }
                } header: {
                    Text(verbatim: "\(title) · \(bucket.label)")
                }
            }
        }
    }

    private func modelRow(_ model: VoiceModel, selected: Bool, select: @escaping (String) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(model.lang.label)
                .font(.ody(size: 9, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(theme.panel, in: Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name).font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                Text(model.humanSize).font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
            }
            Spacer()
            trailing(model, selected: selected, select: select)
        }
        .listRowBackground(theme.bg)
    }

    @ViewBuilder
    private func trailing(_ model: VoiceModel, selected: Bool, select: @escaping (String) -> Void) -> some View {
        if let p = downloads.progress[model.id] {
            HStack(spacing: 8) {
                Text("\(Int(p * 100))%").font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                Button { downloads.cancel(model) } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Cancelar download"))
            }
        } else if downloads.isInstalled(model) {
            HStack(spacing: 16) {
                // Core ML (Neural Engine) acceleration — Whisper STT only.
                if downloads.coreMLAvailable(model) { coreMLControl(model) }
                // Select (use this model)
                Button { select(model.id) } label: {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.ody(size: 20))
                        .foregroundStyle(selected ? theme.green : theme.secondaryText)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Selecionar modelo"))
                .accessibilityAddTraits(selected ? .isSelected : [])
                // Delete
                Button(role: .destructive) { downloads.delete(model) } label: {
                    Image(systemName: "trash").foregroundStyle(theme.accent)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Apagar modelo"))
            }
        } else {
            HStack(spacing: 16) {
                Button { downloads.download(model) } label: {
                    Image(systemName: "arrow.down.circle").font(.ody(size: 20)).foregroundStyle(theme.accent)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Baixar modelo"))
                // A user-added model that failed or was cancelled still holds a
                // row; catalog entries can't be removed, so this is custom-only.
                if model.isCustom {
                    Button(role: .destructive) { downloads.delete(model) } label: {
                        Image(systemName: "trash").foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Apagar modelo"))
                }
            }
        }
    }
}

/// One-shot check of the STT endpoint, running exactly the path a real turn
/// takes: record, then transcribe through `VoiceInputManager`. Setup mistakes —
/// wrong URL, key, model, dialect — surface here as the endpoint's own message
/// instead of as silence in the middle of a conversation. The TTS side has had
/// its "Testar voz" from the start; this is the missing half.
private struct STTTestRow: View {
    @Environment(\.theme) private var theme
    @StateObject private var voice = VoiceInputManager()
    @State private var heard: String?
    @State private var failure: String?

    var body: some View {
        Group {
            Button {
                Task { await toggle() }
            } label: {
                if voice.processing {
                    HStack { ProgressView(); Text("Transcrevendo…") }
                } else if voice.isRecording {
                    Label(L("Gravando… toque para parar"), systemImage: "stop.circle")
                } else {
                    Label(L("Testar reconhecimento"), systemImage: "mic")
                }
            }
            .disabled(voice.processing)

            if let heard {
                Text(L("Ouvi: %@", heard)).font(.footnote)
            }
            if let failure {
                Text(failure).font(.footnote).foregroundStyle(theme.accent)
            }
        }
    }

    private func toggle() async {
        failure = nil
        if voice.isRecording {
            let t = await voice.stop().trimmingCharacters(in: .whitespacesAndNewlines)
            heard = t.isEmpty ? nil : t
            // An empty transcript is the ambiguous case: the endpoint answered
            // 200 with nothing, or it failed and published why. Prefer its own
            // message over a generic one.
            if t.isEmpty { failure = voice.error ?? L("Não captei nenhuma fala.") }
        } else {
            heard = nil
            guard await voice.start() else {
                failure = voice.error ?? L("Microfone indisponível.")
                return
            }
        }
    }
}
