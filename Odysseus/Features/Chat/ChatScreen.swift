import SwiftUI
import PhotosUI
import StoreKit
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct ChatScreen: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.theme) private var theme
    @Environment(\.requestReview) private var requestReview
    @StateObject private var vm: ChatViewModel
    @StateObject private var voice = VoiceInputManager()
    @FocusState private var inputFocused: Bool
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var pasteMonitor: Any?   // macOS ⌘V image-paste event monitor
    @State private var didAutoSend = false
    @State private var showVoice = false
    /// iPhone Duo outer display (or a Face ID phone on its side): the model
    /// menu and a new-chat button go to the toolbar, which sits in the system
    /// rail, and the composer keeps its width for the message.
    @State private var sideRail = false
    /// Settings › Aparência › Personalizar interface.
    @AppStorage(UIVisibility.storageKey) private var uiRaw = ""
    private var ui: UIVisibility { UIVisibility(raw: uiRaw) }
    /// Off = a reading column; the web's `chat-fullwidth`. Only iPad and
    /// Mac are wide enough for the difference to show.
    private var columnWidth: CGFloat? { ui.isOn(.fullWidth) ? nil : Spacing.readableWidth }
    private let autoSend: String?

    init(app: AppState, session: ChatSession?, deepSearch: Bool = false,
         autoSend: String? = nil, onActivity: ((String, Bool) -> Void)? = nil,
         onSessionCreated: @escaping (String) -> Void) {
        let model = app.makeChatViewModel(session: session)
        model.onSessionCreated = onSessionCreated
        model.onActivity = onActivity
        model.research = deepSearch
        _vm = StateObject(wrappedValue: model)
        self.autoSend = autoSend
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                messages
                composer
            }
        }
        #if os(macOS)
        .screenChrome(title: vm.title, subtitle: vm.resolvedModel) {
        } trailing: {
            voiceModeButton
        }
        #else
        .odyNavTitle(vm.title, subtitle: vm.resolvedModel, verbatim: true)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                voiceModeButton
                if sideRail {
                    newChatButton
                    if !vm.models.isEmpty { modelToolbarMenu }
                }
            }
        }
        .readSideRail($sideRail)
        #endif
        .task { await vm.loadModels() }
        .sheet(isPresented: $showVoice) {
            // Hands-free mode continues this same server session, so anything
            // said by voice lands in the very conversation that's open here.
            VoiceView(app: app, session: vm.sessionID, messages: vm.messages)
        }
        .onAppear {
            vm.loadHistoryIfNeeded()
            #if DEBUG
            if let id = ScreenshotRoute.value("voice"), id == vm.sessionID {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { showVoice = true }
            }
            #endif
            // The one moment the app asks for a rating: a reply that just
            // streamed cleanly, gated by ReviewGate. A beat later, never over
            // the last streaming frame.
            // The closure already captures `self` (the view struct) strongly for
            // `requestReview`, and with it `app`; the `[weak app]` only earned the
            // SDK 27 "differs from implicitly-captured strong reference" warning.
            // No cycle either way: `vm` does not own the app-lifetime AppState.
            vm.onReplyCompleted = {
                guard ReviewGate().recordSuccessfulReply(sessionCount: app.sessionCount) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { requestReview() }
            }
            if let p = autoSend, !didAutoSend, !p.isEmpty {
                didAutoSend = true
                vm.input = p
                vm.send()
            }
            #if os(macOS)
            installPasteMonitor()
            #endif
        }
        .onDisappear {
            #if os(macOS)
            if let m = pasteMonitor { NSEvent.removeMonitor(m); pasteMonitor = nil }
            #endif
        }
    }

    // MARK: - Messages

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if vm.isLoadingHistory && vm.messages.isEmpty {
                    ProgressView().tint(theme.accent).padding(.top, 80)
                } else if vm.messages.isEmpty && ui.isOn(.welcome) {
                    welcome.padding(.top, Spacing.voidOffset)
                }
                LazyVStack(spacing: 20) {
                    ForEach(Array(vm.messages.enumerated()), id: \.element.id) { idx, msg in
                        MessageBubble(
                            message: msg,
                            isStreaming: vm.isStreaming && idx == vm.messages.count - 1 && msg.role == .assistant,
                            attachmentURL: vm.attachmentURL
                        )
                        .id(msg.id)
                    }
                    ForEach(vm.notices) { ChatNoticeBanner(notice: $0) }
                    if let ask = vm.pendingAsk {
                        AskUserCard(ask: ask,
                                    onAnswer: { vm.answer(ask, with: $0) },
                                    onDecide: { vm.decide(ask, option: $0) },
                                    onDismiss: { vm.dismissAsk() })
                            .id(ask.id)
                    }
                    if let tool = vm.toolStatus {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(theme.accent)
                            Text(LocalizedStringKey(tool))
                                .font(.ody(.subheadline))
                                .foregroundStyle(theme.secondaryText)
                            Spacer()
                        }
                        .id("toolstatus")
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, 16)
                .frame(maxWidth: columnWidth ?? .infinity)
                .frame(maxWidth: .infinity)
                Color.clear.frame(height: 1).id("bottom")
            }
            .scrollDismissesKeyboard(.interactively)
            .odyRefreshable { await vm.reloadHistory() }
            .onChange(of: vm.messages.last?.content) { _, _ in scrollToBottom(proxy) }
            .onChange(of: vm.messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: vm.toolStatus) { _, _ in scrollToBottom(proxy) }
            .onChange(of: vm.notices.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: vm.pendingAsk) { _, _ in scrollToBottom(proxy) }
            // The "read with the device voice" line lands under the message
            // being read; on the last one it sat behind the chip bar, unseen.
            .onReceive(SpeechManager.shared.$notice) { n in
                if let n, n.id == vm.messages.last?.id { scrollToBottom(proxy) }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            BrandMark(size: 56)
            Text("Como posso ajudar?")
                .font(.ody(.title2).weight(.semibold))
                .foregroundStyle(theme.fg)
            Text("Conectado a \(connectedHost)")
                .font(.ody(.footnote))
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Composer

    /// One rounded box: the field on top, the controls under it. Attach and
    /// the Web / Deep / Agente modes live in the "+" menu; a mode that is on
    /// shows as a chip in the box, and tapping the chip turns it off. The old
    /// layout spent a row on three 27 pt chips and boxed the field on its own.
    private var composer: some View {
        VStack(spacing: 8) {
            if vm.isStreaming { Divider().overlay(theme.border) }

            // `vm.error` covers a failed history load, a failed attachment upload,
            // and a stream error that arrived after the bubble already had text —
            // all three used to be written and never read.
            ForEach([voice.error, vm.error].compactMap { $0 }, id: \.self) { err in
                Label { Text(LocalizedStringKey(err)) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.ody(.footnote))
                .foregroundStyle(theme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.gutter)
            }

            if !vm.pendingAttachments.isEmpty || vm.uploading { pendingStrip }

            VStack(alignment: .leading, spacing: 0) {
                // The placeholder is drawn over the field: a vertical-axis
                // field paints its own (title or `prompt`) in the system sans
                // whatever font it is given.
                TextField("", text: voice.isRecording ? .constant(voice.partialText) : $vm.input, axis: .vertical)
                    .font(.ody(.body))
                    .foregroundStyle(theme.fg)
                    .focused($inputFocused)
                    .lineLimit(1...6)
                    .accessibilityLabel(Text(LocalizedStringKey(composerPlaceholder)))
                    .overlay(alignment: .topLeading) {
                        if (voice.isRecording ? voice.partialText : vm.input).isEmpty {
                            Text(LocalizedStringKey(composerPlaceholder))
                                .font(.ody(.body))
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    #if os(macOS)
                    // Enter sends · Shift+Enter inserts a newline.
                    .onKeyPress(keys: [.return]) { press in
                        if press.modifiers.contains(.shift) { return .ignored }
                        if !voice.isRecording && canSend { vm.send(); inputFocused = false }
                        return .handled
                    }
                    #endif
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                HStack(spacing: 4) {
                    if hasPlusMenu { plusMenu }
                    // Labels while they fit; with every mode on in a narrow
                    // box, the glyphs alone.
                    ViewThatFits(in: .horizontal) {
                        activeChips(labels: true)
                        activeChips(labels: false)
                    }
                    Spacer(minLength: 4)
                    if !vm.models.isEmpty && !sideRail { modelChip }
                    if ui.isOn(.mic) { micButton }
                    sendButton
                    // Key equivalents ride on zero-size buttons: one binding per
                    // button, so Esc cannot also send.
                    Group {
                        Button("") { if vm.isStreaming { vm.stop() } }.keyboardShortcut(OdyShortcuts.stop).disabled(!vm.isStreaming)
                        Button("") { if vm.isStreaming { vm.stop() } }.keyboardShortcut(.escape, modifiers: []).disabled(!vm.isStreaming)
                        Button("") { inputFocused = true }.keyboardShortcut(OdyShortcuts.focusInput)
                    }
                    .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
            .padding(.bottom, 2)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(theme.fg.opacity(0.10), lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: columnWidth ?? .infinity)
        .frame(maxWidth: .infinity)
        .background(theme.bg)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems,
                      maxSelectionCount: 4, matching: .images)
        .onChange(of: photoItems) { _, items in loadPhotos(items) }
    }

    /// Whether anything is left in the "+" menu once Aparência › Personalizar
    /// interface has hidden what the user does not want.
    private var hasPlusMenu: Bool {
        ui.isOn(.attach) || ui.isOn(.webChip) || ui.isOn(.deepChip) || ui.isOn(.agentChip)
    }

    private var plusMenu: some View {
        Menu {
            if ui.isOn(.attach) {
                Button { showPhotoPicker = true } label: {
                    Label("Anexar fotos", systemImage: "photo")
                }
                Divider()
            }
            if ui.isOn(.webChip) {
                Toggle(isOn: $vm.webSearch) { Label("Web", systemImage: "globe") }
            }
            if ui.isOn(.deepChip) {
                Toggle(isOn: $vm.research) { Label("Deep", systemImage: "sparkle.magnifyingglass") }
            }
            if ui.isOn(.agentChip) {
                Toggle(isOn: $vm.agentMode) { Label("Agente", systemImage: "wrench.and.screwdriver") }
            }
        } label: {
            Image(systemName: "plus")
                .font(.ody(.body, weight: .medium))
                .foregroundStyle(theme.fg)
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(theme.fg.opacity(0.14), lineWidth: 1))
                .frame(width: Spacing.tapTarget, height: Spacing.tapTarget)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Mais opções"))
    }

    private func activeChips(labels: Bool) -> some View {
        HStack(spacing: 6) {
            if ui.isOn(.webChip) && vm.webSearch {
                modeChip(system: "globe", label: "Web", labels: labels) { vm.webSearch = false }
            }
            if ui.isOn(.deepChip) && vm.research {
                modeChip(system: "sparkle.magnifyingglass", label: "Deep", labels: labels) { vm.research = false }
            }
            if ui.isOn(.agentChip) && vm.agentMode {
                modeChip(system: "wrench.and.screwdriver", label: "Agente", labels: labels) { vm.agentMode = false }
            }
        }
        .fixedSize()
    }

    /// A mode that is on. Tapping it turns it off; the "+" menu turns it back on.
    private func modeChip(system: String, label: String, labels: Bool,
                          _ turnOff: @escaping () -> Void) -> some View {
        Button(action: turnOff) {
            HStack(spacing: 5) {
                Image(systemName: system).foregroundStyle(theme.accentText)
                if labels {
                    Text(LocalizedStringKey(label)).foregroundStyle(theme.fg).lineLimit(1)
                }
                Image(systemName: "xmark")
                    .font(.ody(.caption, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            .font(.ody(.subheadline))
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(theme.accent.opacity(0.18), in: Capsule())
            .frame(minHeight: Spacing.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(label)))
        .accessibilityAddTraits(.isSelected)
    }

    private var pendingStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.pendingAttachments) { f in
                    ZStack(alignment: .topTrailing) {
                        AsyncImage(url: vm.attachmentURL(f.id)) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: { theme.panel }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        Button { vm.removePending(f) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .accessibilityLabel(Text("Remover"))
                        .offset(x: 5, y: -5)
                    }
                }
                if vm.uploading {
                    ProgressView().frame(width: 56, height: 56)
                        .background(theme.panel, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 12)
        }
    }

    #if os(macOS)
    /// Intercepts ⌘V at the event level so a copied/screenshot image becomes an
    /// attachment. Text pastes are left untouched (we only consume image-only
    /// clipboards), so the message field keeps pasting text normally.
    private func installPasteMonitor() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak vm] event in
            guard event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "v" else { return event }
            let pb = NSPasteboard.general
            guard pb.string(forType: .string) == nil,
                  let img = (pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first,
                  let png = img.odyPNGData() else { return event }   // not an image → let the field paste text
            Task { @MainActor in await vm?.addImages([(png, "colado.png", "image/png")]) }
            return nil   // consume the ⌘V
        }
    }
    #endif

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var files: [(data: Data, filename: String, mime: String)] = []
            for (i, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    files.append((data, "image\(i).jpg", "image/jpeg"))
                }
            }
            await vm.addImages(files)
            photoItems = []
        }
    }

    /// Hands-free voice mode. Distinct from the mic in the composer, which only
    /// dictates into the text field.
    private var voiceModeButton: some View {
        Button { showVoice = true } label: {
            Image(systemName: "waveform")
                .font(.ody(.body))
                .foregroundStyle(theme.fg)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Conversar por voz"))
    }

    private var micButton: some View {
        Button {
            Task { await toggleMic() }
        } label: {
            ZStack {
                if voice.processing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic")
                        .font(.ody(.title3))
                        .foregroundStyle(voice.isRecording ? theme.accentText : theme.fg)
                        .symbolEffect(.pulse, isActive: voice.isRecording)
                }
            }
            .frame(width: 36, height: Spacing.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(voice.processing)
        .accessibilityLabel(Text("Microfone"))
        .accessibilityAddTraits(voice.isRecording ? .isSelected : [])
    }

    private func toggleMic() async {
        if voice.isRecording {
            let text = await voice.stop()
            if !text.isEmpty {
                vm.input = (vm.input.isEmpty ? "" : vm.input + " ") + text
            }
            inputFocused = true
        } else {
            _ = await voice.start()
        }
    }

    private var sendButton: some View {
        Button {
            if vm.isStreaming { vm.stop() }
            else { vm.send(); inputFocused = false }
        } label: {
            let live = canSend || vm.isStreaming
            Image(systemName: vm.isStreaming ? "stop.fill" : "arrow.up")
                .font(.ody(.body, weight: .bold))
                .foregroundStyle(live ? theme.onAccent : theme.fg.opacity(0.45))
                .frame(width: 34, height: 34)
                .background(live ? theme.accentFill : theme.fg.opacity(0.12), in: Circle())
                .frame(width: Spacing.tapTarget, height: Spacing.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend && !vm.isStreaming)
        .keyboardShortcut(OdyShortcuts.send)
        .accessibilityLabel(Text(LocalizedStringKey(vm.isStreaming ? "Parar resposta" : "Enviar mensagem")))
    }

    private var connectedHost: String {
        #if DEBUG
        if let label = ScreenshotRoute.hostLabel { return label }
        #endif
        return app.serverConfig.baseURL.host ?? "Odysseus"
    }

    private var composerPlaceholder: String { voice.isRecording ? "Ouvindo…" : "Mensagem…" }

    private var canSend: Bool {
        !vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !vm.pendingAttachments.isEmpty
    }

    /// Model route for the next message. Hidden entirely when the server lists
    /// no models, so nothing changes on a server without a picker.
    @ViewBuilder private var modelMenuItems: some View {
        Button("Padrão do servidor") { vm.selectedModel = nil }
        Divider()
        ForEach(vm.models.filter { !$0.isExtra }) { m in
            Button(m.name) { vm.selectedModel = m }
        }
        // The non-curated rest (`models_extra`) is buried in a submenu —
        // it can run to hundreds of entries on a cloud endpoint.
        let extras = vm.models.filter(\.isExtra)
        if !extras.isEmpty {
            Menu("Outros modelos") {
                ForEach(extras) { m in Button(m.name) { vm.selectedModel = m } }
            }
        }
    }

    /// The same menu as a bar button, for the side rail. The name in use is
    /// already the subtitle under the title.
    private var modelToolbarMenu: some View {
        Menu { modelMenuItems } label: {
            Image(systemName: "cpu")
                .font(.ody(.body))
                .foregroundStyle(vm.selectedModel == nil ? theme.fg : theme.accentText)
        }
        .disabled(vm.isStreaming)
        .accessibilityLabel(Text("Modelo"))
        .accessibilityValue(Text(verbatim: vm.selectedModel?.name ?? vm.resolvedModel ?? L("Padrão do servidor")))
    }

    private var newChatButton: some View {
        Button { NotificationCenter.default.post(name: .odysseusNewChat, object: nil) } label: {
            Image(systemName: "square.and.pencil")
                .font(.ody(.body))
                .foregroundStyle(theme.fg)
        }
        .accessibilityLabel(Text("Nova conversa"))
    }

    private var modelChip: some View {
        Menu { modelMenuItems } label: {
            // Plain text inside the box: a bordered capsule in a bordered box
            // was one frame too many.
            HStack(spacing: 3) {
                Text(vm.selectedModel?.name ?? vm.resolvedModel ?? L("Modelo"))
                    // Cut at the end: "mimo-v2.6-pro" reads, "mimo…6-pro" does not.
                    .lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.ody(.caption))
                    .accessibilityHidden(true)
            }
            .font(.ody(.subheadline))
            .foregroundStyle(vm.selectedModel == nil ? theme.secondaryText : theme.accentText)
            .padding(.horizontal, 6)
            .frame(minHeight: Spacing.tapTarget)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(maxWidth: 150, alignment: .trailing)
        .accessibilityLabel(Text("Modelo"))
        .accessibilityValue(Text(verbatim: vm.selectedModel?.name ?? vm.resolvedModel ?? L("Padrão do servidor")))
        .disabled(vm.isStreaming)
    }
}

#if os(macOS)
extension NSImage {
    /// Re-encodes any image (incl. pasted TIFF screenshots) as PNG for upload.
    func odyPNGData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
