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
/// Nothing persisted is mirrored here: every stored field lives in
/// `EndpointConfig` at the bottom of this file, which is also where the reason
/// for that is written down.
struct VoiceEndpointFields: View {
    let kind: VoiceEndpoint.Kind

    @Environment(\.theme) private var theme

    /// Starts hidden so an over-the-shoulder glance doesn't read the key, and
    /// because a long token is unreadable in a single line anyway.
    @State private var showKey = false
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

    /// Everything persisted, in one observable place. See `EndpointConfig`.
    @StateObject private var config: EndpointConfig

    init(kind: VoiceEndpoint.Kind) {
        self.kind = kind
        _config = StateObject(wrappedValue: EndpointConfig(kind: kind))
    }

    // MARK: - Which provider this is

    /// Fish is reachable two ways and the two disagree on the model namespace,
    /// so which one is in use has to be a state, not a pair of booleans read
    /// differently at each site.
    private enum Provider { case fishNative, fishCompat, generic }

    private var provider: Provider {
        if config.dialect == .fish { return .fishNative }
        // Fish's own catalogue and model names apply whenever the endpoint
        // points at Fish, whether through its native API or its
        // OpenAI-compatible layer.
        return config.url.contains("fish.audio") ? .fishCompat : .generic
    }

    private var isTTS: Bool { kind == .tts }

    private var urlHint: String {
        switch provider {
        case .fishNative:           return "https://api.fish.audio/v1"
        case .fishCompat, .generic: return "https://meu.servidor/v1"
        }
    }

    /// An explicit `http://` is honoured — a self-hosted box on the LAN often
    /// has no certificate, and refusing would break the main use case. But the
    /// Authorization header rides along in the clear, so say so. A schemeless
    /// entry is upgraded to https by `VoiceEndpoint.config`, so only a
    /// deliberate `http://` reaches here.
    private var cleartextWarning: Bool {
        let u = config.url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return u.hasPrefix("http://") && !config.key.isEmpty
    }
    /// Fish's /asr takes no model at all, so the row is hidden rather than
    /// offered and ignored.
    private var showsModel: Bool {
        switch provider {
        case .fishNative:           return isTTS
        case .fishCompat, .generic: return true
        }
    }
    private var modelHint: String {
        // Modality first: on a Fish host the STT field used to suggest
        // "s2.1-pro", which is a *speech* model — the exact value that earned a
        // 400 from Fish saying so.
        guard isTTS else { return "whisper-1" }
        switch provider {
        case .fishNative, .fishCompat: return "s2.1-pro"
        case .generic:                 return "tts-1"
        }
    }

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
        guard isTTS else { return [] }
        switch provider {
        // Fish's own API takes the bare engine name; its OpenAI-compatible
        // layer wants the vendor namespace.
        case .fishNative: return VoiceEndpoint.fishModels
        case .fishCompat: return VoiceEndpoint.fishModels.map { "fish-audio/" + $0 }
        case .generic:    return []
        }
    }

    /// Picker selection is the model id itself; an id not on the list selects
    /// "Outro…" and stays editable, so neither a stale build nor a server that
    /// hides a model can lock anyone out.
    private var modelChoice: Binding<String> {
        Binding(
            get: {
                if customMode { return customModelTag }
                let current = config.model
                if current.isEmpty { return offered.first ?? customModelTag }
                return offered.contains(current) ? current : customModelTag
            },
            set: { picked in
                guard picked != customModelTag else { customMode = true; return }
                customMode = false
                config.model = picked
            }
        )
    }

    /// Brings the stored model back in step with whatever `offered` now holds.
    ///
    /// A SwiftUI Picker only runs its binding's `set()` when the user taps a
    /// row — never because `get()` started returning something else. So with
    /// nothing stored, the Picker displayed `offered.first` while the request
    /// went out carrying no `model` field at all, which OpenAI rejects.
    private func reconcileModel() {
        let current = config.model
        if current.isEmpty, let first = offered.first {
            config.model = first
            customMode = false
            return
        }
        customMode = !current.isEmpty && !offered.isEmpty && !offered.contains(current)
    }

    var body: some View {
        Group {
            Picker(L("Formato"), selection: $config.dialect) {
                ForEach(VoiceEndpoint.Dialect.allCases, id: \.rawValue) { d in
                    Text(d.label).tag(d)
                }
            }
            .onChange(of: config.dialect) { _, _ in
                // A different dialect is a different server contract: the model
                // namespace changes ("s2.1-pro" vs "fish-audio/s2.1-pro") and a
                // carried-over value fails with no visible cause.
                discovered = []
                customMode = false
                config.clearModelAndVoice()
            }

            TextField(L("URL base"), text: $config.url, prompt: Text(verbatim: urlHint))
                .textContentType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .onChange(of: config.url) { _, _ in
                    // The list belongs to the server that answered the probe,
                    // not to the one now being typed in.
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
                        TextField(L("Chave da API"), text: $config.key)
                    } else {
                        SecureField(L("Chave da API"), text: $config.key)
                    }
                }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
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
                    TextField(L("Modelo"), text: $config.model, prompt: Text(verbatim: modelHint))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    Picker(L("Modelo"), selection: modelChoice) {
                        ForEach(offered, id: \.self) { Text($0).tag($0) }
                        Text("Outro…").tag(customModelTag)
                    }
                    if customMode || modelChoice.wrappedValue == customModelTag {
                        TextField(L("Nome do modelo"), text: $config.model,
                                  prompt: Text(verbatim: "s3-pro"))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
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
                .disabled(config.url.isEmpty || probing)

                if let probeError {
                    Text(probeError).font(.footnote).foregroundStyle(theme.accent)
                }
            }

            if isTTS {
                switch provider {
                case .fishNative, .fishCompat:
                    Button {
                        pickingVoice = true
                    } label: {
                        HStack {
                            Text("Voz").foregroundStyle(.primary)
                            Spacer()
                            Text(config.voiceTitle.isEmpty ? L("Escolher…")
                                                                 : config.voiceTitle)
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .sheet(isPresented: $pickingVoice) {
                        FishVoicePicker { id, title in
                            config.voice = id
                            config.voiceTitle = title
                        }
                    }
                case .generic:
                    TextField(L("Voz"), text: $config.voice, prompt: Text(verbatim: "alloy"))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
        }
        .onAppear { reconcileModel() }
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
                    probeError = L("O modelo guardado (%@) não está na lista do servidor.", config.model)
                }
            }
        } catch {
            probeError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// One speech endpoint's stored configuration, as an observable object.
///
/// This is the whole reason the view holds no mirrored `@State`. The fields
/// used to be six `@State` properties, and the same six keys were then written
/// out in three separate places that had to stay in step: an `onAppear` that
/// loaded them, one `onChange` per field that wrote them back, and a dialect
/// handler that cleared four of them. A seventh field meant editing all three
/// lists, and missing one meant a setting that silently did not stick.
///
/// `@AppStorage` cannot own these: it needs a compile-time key, and every key
/// here depends on whether this is the STT or the TTS half (`Kind.urlKey` and
/// friends). Binding straight to `UserDefaults` instead would work but leaves
/// SwiftUI nothing to observe, so the view would need a hand-turned counter to
/// force redraws — and reading the Keychain from a getter would run
/// `SecItemCopyMatching` on every body evaluation. Loading once here and
/// publishing changes is what both of those were working around.
@MainActor
final class EndpointConfig: ObservableObject {
    private let kind: VoiceEndpoint.Kind

    @Published var url: String       { didSet { write(url, kind.urlKey) } }
    @Published var model: String     { didSet { write(model, kind.modelKey) } }
    @Published var voice: String     { didSet { write(voice, kind.voiceKey) } }
    @Published var voiceTitle: String { didSet { write(voiceTitle, kind.voiceTitleKey) } }
    @Published var dialect: VoiceEndpoint.Dialect {
        didSet { write(dialect.rawValue, kind.dialectKey) }
    }
    /// The Keychain, not UserDefaults — `UserDefaults` lands in the iCloud
    /// backup as plain text. An emptied field means "forget it", not "store an
    /// empty string", or the Authorization header goes out as "Bearer ".
    @Published var key: String {
        didSet {
            if key.isEmpty { _ = Keychain.delete(kind.secretKey) }
            else { _ = Keychain.set(key, for: kind.secretKey) }
        }
    }

    init(kind: VoiceEndpoint.Kind) {
        // Assignments during initialization do not fire `didSet`, so loading
        // here cannot write the values straight back out.
        self.kind = kind
        let d = UserDefaults.standard
        url = d.string(forKey: kind.urlKey) ?? ""
        model = d.string(forKey: kind.modelKey) ?? ""
        voice = d.string(forKey: kind.voiceKey) ?? ""
        voiceTitle = d.string(forKey: kind.voiceTitleKey) ?? ""
        dialect = VoiceEndpoint.Dialect(rawValue: d.string(forKey: kind.dialectKey) ?? "") ?? .openai
        key = Keychain.get(kind.secretKey) ?? ""
    }

    /// A different dialect is a different server contract, so what was chosen
    /// under the old one cannot carry over.
    func clearModelAndVoice() {
        model = ""; voice = ""; voiceTitle = ""
    }

    private func write(_ value: String, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
