import SwiftUI

struct VoiceSettingsView: View {
    @Environment(\.theme) private var theme
    @StateObject private var downloads = ModelDownloadManager.shared
    @ObservedObject private var speech = SpeechManager.shared

    @AppStorage("voice.stt.engine") private var sttEngine = "native"
    @AppStorage("voice.stt.model") private var sttModelID = ""
    @AppStorage("voice.tts.engine") private var ttsEngine = "native"
    @AppStorage("voice.tts.pocketVoice") private var pocketVoice = "alba"
    @State private var langFilter = "all"

    private var lang: VoiceLang? { VoiceLang(rawValue: langFilter) }

    var body: some View {
        List {
            Section {
                Picker("Reconhecimento (STT)", selection: $sttEngine) {
                    Text("Nativo iOS").tag("native")
                    Text("Modelo on-device").tag("model")
                }
                if sttEngine == "model" {
                    LabeledContent("Modelo ativo", value: modelName(sttModelID) ?? "nenhum")
                }
            } header: { Text("Voz → Texto") } footer: {
                Text("Nativo = transcrição ao vivo enquanto você fala (tipo Claude/Gemini). \"Modelo\" = Whisper offline (transcreve no fim). Nos modelos baixados, o ⚡ baixa o acelerador Core ML (Neural Engine) → bem mais rápido.")
            }

            Section {
                Picker("Voz da IA (TTS)", selection: $ttsEngine) {
                    Text("Nativo iOS").tag("native")
                    Text("Neural pt-BR").tag("neural")
                }
                if ttsEngine == "neural" {
                    Picker("Voz", selection: $pocketVoice) {
                        ForEach(PocketVoices.portuguese, id: \.self) { Text($0).tag($0) }
                    }
                    Button { speech.prepareNeural() } label: {
                        if speech.isPreparing("__prepare__") {
                            HStack { ProgressView(); Text("Baixando voz neural…") }
                        } else if speech.neuralReady {
                            Label("Voz neural pronta", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(theme.green)
                        } else {
                            Label("Baixar voz neural (~550 MB)", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(speech.isPreparing("__prepare__") || speech.neuralReady)
                    if let e = speech.neuralError {
                        Text(e).font(.footnote).foregroundStyle(theme.accent)
                    }
                }
            } header: { Text("Texto → Voz") } footer: {
                Text("Neural = PocketTTS em português (CoreML/Neural Engine), bem mais natural que a voz nativa. Baixa ~550 MB on-device na primeira vez; roda só no iPhone físico (não no simulador).")
            }

            Section("Filtrar catálogo por idioma") {
                Picker("Idioma", selection: $langFilter) {
                    Text("Todos").tag("all")
                    ForEach(VoiceLang.allCases, id: \.rawValue) { l in
                        Text("\(l.flag) \(l.label)").tag(l.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            modelSection(title: "Modelos STT · Whisper", task: .stt,
                         selectedID: sttModelID) { id in sttModelID = id; sttEngine = "model" }

            if downloads.totalInstalledBytes() > 0 {
                Section {
                    LabeledContent("Espaço usado",
                                   value: ByteCountFormatter.string(fromByteCount: downloads.totalInstalledBytes(), countStyle: .file))
                }
            }
        }
        .navigationTitle("Voz e modelos")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .tint(theme.accent)
        .onAppear { downloads.refresh() }
        .alert("Erro no download", isPresented: Binding(get: { downloads.error != nil }, set: { if !$0 { downloads.error = nil } })) {
            Button("OK") { downloads.error = nil }
        } message: { Text(downloads.error ?? "") }
    }

    private func modelName(_ id: String) -> String? {
        VoiceCatalog.all.first { $0.id == id }?.name
    }

    /// ⚡ = Core ML / Neural Engine acceleration for a Whisper model.
    @ViewBuilder
    private func coreMLControl(_ model: VoiceModel) -> some View {
        if let p = downloads.coreMLProgress(model) {
            HStack(spacing: 4) {
                Text("\(Int(p * 100))%").font(.ody(size: 9, design: .monospaced)).foregroundStyle(theme.secondaryText)
                Button { downloads.cancelCoreML(model) } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless)
            }
        } else if downloads.hasCoreML(model) {
            Button { downloads.deleteCoreML(model) } label: {
                Image(systemName: "bolt.fill").font(.ody(size: 18)).foregroundStyle(theme.green)
            }
            .buttonStyle(.borderless)
        } else {
            Button { downloads.downloadCoreML(model) } label: {
                Image(systemName: "bolt").font(.ody(size: 18)).foregroundStyle(theme.secondaryText)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func modelSection(title: String, task: VoiceTask, selectedID: String, select: @escaping (String) -> Void) -> some View {
        let models = VoiceCatalog.filtered(task: task, lang: lang)
        ForEach(VoiceModel.Bucket.allCases, id: \.rawValue) { bucket in
            let items = models.filter { $0.bucket == bucket }
            if !items.isEmpty {
                Section("\(title) · \(bucket.rawValue)") {
                    ForEach(items) { model in
                        modelRow(model, selected: selectedID == model.id, select: select)
                    }
                }
            }
        }
    }

    private func modelRow(_ model: VoiceModel, selected: Bool, select: @escaping (String) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(model.lang.flag)
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
                // Delete
                Button(role: .destructive) { downloads.delete(model) } label: {
                    Image(systemName: "trash").foregroundStyle(theme.accent)
                }
                .buttonStyle(.borderless)
            }
        } else {
            Button { downloads.download(model) } label: {
                Image(systemName: "arrow.down.circle").font(.ody(size: 20)).foregroundStyle(theme.accent)
            }
            .buttonStyle(.borderless)
        }
    }
}
