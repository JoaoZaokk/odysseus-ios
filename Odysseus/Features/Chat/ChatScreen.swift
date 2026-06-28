import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct ChatScreen: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.theme) private var theme
    @StateObject private var vm: ChatViewModel
    @StateObject private var voice = VoiceInputManager()
    @FocusState private var inputFocused: Bool
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pasteMonitor: Any?   // macOS ⌘V image-paste event monitor
    @State private var didAutoSend = false
    private let autoSend: String?

    init(app: AppState, session: ChatSession?, deepSearch: Bool = false,
         autoSend: String? = nil, onSessionCreated: @escaping (String) -> Void) {
        let model = app.makeChatViewModel(session: session)
        model.onSessionCreated = onSessionCreated
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
        .screenChrome(title: vm.title, subtitle: vm.resolvedModel)
        #else
        .navigationTitle(vm.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(vm.title)
                        .font(.ody(.headline, design: .monospaced))
                        .foregroundStyle(theme.fg)
                        .lineLimit(1)
                    if let m = vm.resolvedModel {
                        Text(m)
                            .font(.ody(size: 10, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
        }
        #endif
        .onAppear {
            vm.loadHistoryIfNeeded()
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
                } else if vm.messages.isEmpty {
                    welcome.padding(.top, 60)
                }
                LazyVStack(spacing: 16) {
                    ForEach(Array(vm.messages.enumerated()), id: \.element.id) { idx, msg in
                        MessageBubble(
                            message: msg,
                            isStreaming: vm.isStreaming && idx == vm.messages.count - 1 && msg.role == .assistant,
                            attachmentURL: vm.attachmentURL
                        )
                        .id(msg.id)
                    }
                    if let tool = vm.toolStatus {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(theme.accent)
                            Text(LocalizedStringKey(tool))
                                .font(.ody(size: 12, design: .monospaced))
                                .foregroundStyle(theme.secondaryText)
                            Spacer()
                        }
                        .id("toolstatus")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                Color.clear.frame(height: 1).id("bottom")
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await vm.reloadHistory() }
            .onChange(of: vm.messages.last?.content) { _, _ in scrollToBottom(proxy) }
            .onChange(of: vm.messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: vm.toolStatus) { _, _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            BrandMark(size: 56)
            Text("Como posso ajudar?")
                .font(.ody(.title2, design: .monospaced).weight(.semibold))
                .foregroundStyle(theme.fg)
            Text("Conectado a \(app.serverConfig.baseURL.host ?? "Odysseus")")
                .font(.ody(.footnote, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if vm.isStreaming { Divider().overlay(theme.border) }
            HStack(spacing: 8) {
                toggleChip(system: "globe", label: "Web", on: $vm.webSearch)
                toggleChip(system: "sparkle.magnifyingglass", label: "Deep", on: $vm.research)
                toggleChip(system: "wrench.and.screwdriver", label: "Agente", on: $vm.agentMode)
                Spacer()
            }
            .padding(.horizontal, 12)

            if let err = voice.error {
                Text(err)
                    .font(.ody(size: 11, design: .monospaced))
                    .foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }

            if !vm.pendingAttachments.isEmpty || vm.uploading { pendingStrip }

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                        .font(.ody(size: 20))
                        .foregroundStyle(theme.accent)
                        .frame(width: 34, height: 42)
                }
                .onChange(of: photoItems) { _, items in loadPhotos(items) }

                micButton

                TextField(LocalizedStringKey(voice.isRecording ? "Ouvindo…" : "Mensagem…"),
                          text: voice.isRecording ? .constant(voice.partialText) : $vm.input, axis: .vertical)
                    .font(.ody(.body, design: .monospaced))
                    .foregroundStyle(theme.fg)
                    .focused($inputFocused)
                    .lineLimit(1...6)
                    #if os(macOS)
                    // Enter sends · Shift+Enter inserts a newline.
                    .onKeyPress(keys: [.return]) { press in
                        if press.modifiers.contains(.shift) { return .ignored }
                        if !voice.isRecording && canSend { vm.send(); inputFocused = false }
                        return .handled
                    }
                    #endif
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(theme.panel, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.border, lineWidth: 1))

                sendButton
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(theme.bg)
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

    private var micButton: some View {
        Button {
            Task { await toggleMic() }
        } label: {
            ZStack {
                if voice.processing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic")
                        .font(.ody(size: 20))
                        .foregroundStyle(voice.isRecording ? theme.accent : theme.secondaryText)
                        .symbolEffect(.pulse, isActive: voice.isRecording)
                }
            }
            .frame(width: 34, height: 42)
        }
        .disabled(voice.processing)
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
            Image(systemName: vm.isStreaming ? "stop.fill" : "arrow.up")
                .font(.ody(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(canSend || vm.isStreaming ? theme.accent : theme.border,
                            in: Circle())
        }
        .disabled(!canSend && !vm.isStreaming)
    }

    private var canSend: Bool {
        !vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !vm.pendingAttachments.isEmpty
    }

    private func toggleChip(system: String, label: String, on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: system).font(.ody(size: 11))
                Text(LocalizedStringKey(label)).font(.ody(size: 12, design: .monospaced))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(on.wrappedValue ? .white : theme.secondaryText)
            .background(on.wrappedValue ? theme.accent : theme.panel,
                        in: Capsule())
            .overlay(Capsule().stroke(theme.border, lineWidth: on.wrappedValue ? 0 : 1))
        }
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
