import SwiftUI

/// The URL / key / model rows for a user-configured speech endpoint, shared by
/// the STT and TTS sections of `VoiceSettingsView`.
///
/// The model row is populated by asking the endpoint what it serves (`GET
/// /models`) rather than from a list baked into the app: a build from six months
/// ago should still offer whatever the server added yesterday. Endpoints with no
/// such route fall back to a known list, and "Outro…" always allows a name this
/// build has never heard of.
///
/// The key lives in the Keychain rather than `@AppStorage`, so it is held in
/// local state and written on change instead of being bound to a default.
struct VoiceEndpointFields: View {
    let kind: VoiceEndpoint.Kind

    @Environment(\.theme) private var theme
    @State private var url = ""
    @State private var model = ""
    @State private var voice = ""
    @State private var key = ""
    /// Starts hidden so an over-the-shoulder glance doesn't read the key, and
    /// because a long token is unreadable in a single line anyway.
    @State private var showKey = false
    @State private var dialect = VoiceEndpoint.Dialect.openai.rawValue
    @State private var voiceTitle = ""
    @State private var pickingVoice = false

    /// What the endpoint said it serves. Empty until a probe succeeds.
    @State private var discovered: [String] = []
    @State private var probing = false
    @State private var probeError: String?

    /// Picker tag for "not one of the names offered here".
    private let customModelTag = "__custom__"
    /// Sticky, rather than derived from the stored value: deriving it meant
    /// choosing "Outro…" wrote an empty model, which made the getter fall back
    /// to the first offered name, which snapped the picker off "Outro…" before
    /// the text field could ever appear.
    @State private var customMode = false

    private var isTTS: Bool { kind == .tts }
    private var isFish: Bool { dialect == VoiceEndpoint.Dialect.fish.rawValue }
    /// Fish's own catalogue and model names apply whenever the endpoint points
    /// at Fish, whether through its native API or its OpenAI-compatible layer.
    private var isFishHost: Bool { url.contains("fish.audio") }

    private var urlHint: String {
        isFish ? "https://api.fish.audio/v1" : "https://meu.servidor/v1"
    }

    /// An explicit `http://` is honoured — a self-hosted box on the LAN often
    /// has no certificate, and refusing would break the main use case. But the
    /// Authorization header rides along in the clear, so say so. A schemeless
    /// entry is upgraded to https by `VoiceEndpoint.config`, so only a
    /// deliberate `http://` reaches here.
    private var cleartextWarning: Bool {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return u.hasPrefix("http://") && !key.isEmpty
    }
    /// Fish's /asr takes no model at all, so the row is hidden rather than
    /// offered and ignored.
    private var showsModel: Bool { !(isFish && !isTTS) }
    private var modelHint: String {
        // Modality first: on a Fish host the STT field used to suggest
        // "s2.1-pro", which is a *speech* model — the exact value that earned a
        // 400 from Fish saying so.
        guard isTTS else { return "whisper-1" }
        return isFishHost ? "s2.1-pro" : "tts-1"
    }
    private var voiceHint: String { isFish ? "reference_id" : "alloy" }

    /// Discovery wins; a Fish endpoint with no /models route falls back to the
    /// engine names from its docs; anything else gets a plain text field.
    ///
    /// These are full model ids, exactly as they go on the wire. An earlier
    /// version kept the fallback bare and bolted a namespace on at write time,
    /// which changed meaning the moment a probe succeeded: the prefix vanished,
    /// a stored `fish-audio/s2.1-pro` matched nothing in the new list, and the
    /// Picker flipped itself to "Outro…" with no explanation.
    private var offered: [String] {
        if !discovered.isEmpty { return discovered }
        // s2.1-pro and friends are *speech* engines. Offering them for
        // transcription earned a 400 from Fish saying exactly that, so the
        // fallback list is TTS-only.
        guard isFish || isFishHost, isTTS else { return [] }
        // Fish's own API takes the bare engine name; its OpenAI-compatible
        // layer wants the vendor namespace.
        let ns = isFish ? "" : "fish-audio/"
        return VoiceEndpoint.fishModels.map { ns + $0 }
    }

    private func store(_ name: String) {
        model = name
        UserDefaults.standard.set(name, forKey: kind.modelKey)
    }

    /// Picker selection is the model id itself; an id not on the list selects
    /// "Outro…" and stays editable, so neither a stale build nor a server that
    /// hides a model can lock anyone out.
    private var modelChoice: Binding<String> {
        Binding(
            get: {
                if customMode { return customModelTag }
                if model.isEmpty { return offered.first ?? customModelTag }
                return offered.contains(model) ? model : customModelTag
            },
            set: { picked in
                guard picked != customModelTag else { customMode = true; return }
                customMode = false
                store(picked)
            }
        )
    }

    private var customModel: Binding<String> {
        Binding(get: { model }, set: { store($0) })
    }

    /// Brings the stored model back in step with whatever `offered` now holds.
    ///
    /// A SwiftUI Picker only runs its binding's `set()` when the user taps a
    /// row — never because `get()` started returning something else. So with
    /// nothing stored, the Picker displayed `offered.first` while the request
    /// went out carrying no `model` field at all, which OpenAI rejects.
    private func reconcileModel() {
        if model.isEmpty, let first = offered.first {
            store(first)
            customMode = false
            return
        }
        customMode = !model.isEmpty && !offered.isEmpty && !offered.contains(model)
    }

    var body: some View {
        Group {
            Picker(L("Formato"), selection: $dialect) {
                ForEach(VoiceEndpoint.Dialect.allCases, id: \.rawValue) { d in
                    Text(d.label).tag(d.rawValue)
                }
            }
            .onChange(of: dialect) { _, v in
                let d = UserDefaults.standard
                d.set(v, forKey: kind.dialectKey)
                // A different dialect is a different server contract: the model
                // namespace changes ("s2.1-pro" vs "fish-audio/s2.1-pro") and a
                // carried-over value fails with no visible cause.
                discovered = []
                customMode = false
                model = ""; d.set("", forKey: kind.modelKey)
                voice = ""; voiceTitle = ""
                d.set("", forKey: kind.voiceKey); d.set("", forKey: kind.voiceTitleKey)
            }

            TextField(L("URL base"), text: $url, prompt: Text(verbatim: urlHint))
                .textContentType(.URL)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .onChange(of: url) { _, v in
                    UserDefaults.standard.set(v, forKey: kind.urlKey)
                    discovered = []
                }

            if cleartextWarning {
                Label(L("Sem HTTPS a chave da API viaja em texto puro pela rede."),
                      systemImage: "lock.open")
                    .font(.footnote)
                    .foregroundStyle(theme.accent)
            }

            HStack {
                Group {
                    if showKey {
                        TextField(L("Chave da API"), text: $key)
                    } else {
                        SecureField(L("Chave da API"), text: $key)
                    }
                }
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onChange(of: key) { _, v in
                    // An emptied field means "forget it", not "store an empty
                    // string" — otherwise the Authorization header goes out as
                    // "Bearer ".
                    if v.isEmpty { _ = Keychain.delete(kind.secretKey) }
                    else { _ = Keychain.set(v, for: kind.secretKey) }
                }
                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
                .accessibilityLabel(showKey ? L("Ocultar chave") : L("Mostrar chave"))
            }

            if showsModel {
                if offered.isEmpty {
                    TextField(L("Modelo"), text: $model, prompt: Text(verbatim: modelHint))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onChange(of: model) { _, v in
                            UserDefaults.standard.set(v, forKey: kind.modelKey)
                        }
                } else {
                    Picker(L("Modelo"), selection: modelChoice) {
                        ForEach(offered, id: \.self) { Text($0).tag($0) }
                        Text("Outro…").tag(customModelTag)
                    }
                    if customMode || modelChoice.wrappedValue == customModelTag {
                        TextField(L("Nome do modelo"), text: customModel,
                                  prompt: Text(verbatim: "s3-pro"))
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }
                }

                Button {
                    Task { await probe() }
                } label: {
                    if probing {
                        HStack { ProgressView(); Text("Consultando…") }
                    } else {
                        Label(discovered.isEmpty ? L("Buscar modelos do servidor")
                                                 : L("Atualizar lista (%d)", discovered.count),
                              systemImage: "arrow.clockwise")
                    }
                }
                .disabled(url.isEmpty || probing)

                if let probeError {
                    Text(probeError).font(.footnote).foregroundStyle(theme.accent)
                }
            }

            if isTTS && (isFish || isFishHost) {
                Button {
                    pickingVoice = true
                } label: {
                    HStack {
                        Text("Voz").foregroundStyle(.primary)
                        Spacer()
                        Text(voiceTitle.isEmpty ? L("Escolher…") : voiceTitle)
                            .foregroundStyle(theme.accent)
                    }
                }
                .sheet(isPresented: $pickingVoice) {
                    FishVoicePicker { id, title in
                        voice = id; voiceTitle = title
                        let d = UserDefaults.standard
                        d.set(id, forKey: kind.voiceKey)
                        d.set(title, forKey: kind.voiceTitleKey)
                    }
                }
            } else if isTTS {
                TextField(L("Voz"), text: $voice, prompt: Text(verbatim: voiceHint))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onChange(of: voice) { _, v in
                        UserDefaults.standard.set(v, forKey: kind.voiceKey)
                    }
            }
        }
        .onAppear {
            let d = UserDefaults.standard
            url = d.string(forKey: kind.urlKey) ?? ""
            model = d.string(forKey: kind.modelKey) ?? ""
            voice = d.string(forKey: kind.voiceKey) ?? ""
            key = Keychain.get(kind.secretKey) ?? ""
            dialect = d.string(forKey: kind.dialectKey) ?? VoiceEndpoint.Dialect.openai.rawValue
            voiceTitle = d.string(forKey: kind.voiceTitleKey) ?? ""
            reconcileModel()
        }
    }

    /// A failed probe is not an error state: plenty of perfectly good endpoints
    /// have no /models route. It just leaves the fallback in place, with the
    /// reason visible for the case where the URL or key is actually wrong.
    private func probe() async {
        probing = true; probeError = nil
        defer { probing = false }
        do {
            let names = try await VoiceEndpoint.listModels(kind)
            if names.isEmpty {
                probeError = L("O servidor não listou nenhum modelo.")
            } else {
                discovered = names
                // The list just changed under the selection. Adopt a default if
                // nothing was stored, and say so when the stored id isn't one
                // the server offers, instead of quietly switching the Picker to
                // "Outro…" and leaving a name on screen nobody chose.
                reconcileModel()
                if customMode {
                    probeError = L("O modelo guardado (%@) não está na lista do servidor.", model)
                }
            }
        } catch {
            probeError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
