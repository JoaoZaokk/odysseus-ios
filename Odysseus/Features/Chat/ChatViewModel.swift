import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var input: String = ""
    @Published var isStreaming = false
    @Published var isLoadingHistory = false
    @Published var toolStatus: String?
    @Published var resolvedModel: String?
    @Published var error: String?
    /// Context trims / agent guards raised during the last reply. Unlike
    /// `toolStatus` these survive the end of the stream — they explain the reply
    /// the user is left looking at.
    @Published var notices: [ChatNotice] = []

    // Composer toggles
    @Published var agentMode = false
    @Published var webSearch = false
    @Published var research = false

    // Attachments staged for the next message
    @Published var pendingAttachments: [UploadedFile] = []
    @Published var uploading = false

    /// nil until the conversation is materialized server-side (new chat).
    @Published private(set) var sessionID: String?
    @Published var title: String

    /// Fired with the new session id the first time a brand-new chat is created,
    /// so the sidebar can refresh.
    var onSessionCreated: ((String) -> Void)?

    private let api: APIClient
    private let stream: ChatStreamClient
    private var streamTask: Task<Void, Never>?

    init(api: APIClient, stream: ChatStreamClient, session: ChatSession?) {
        self.api = api
        self.stream = stream
        self.sessionID = session?.id
        self.title = session?.title ?? "Nova conversa"
        self.resolvedModel = session?.shortModel
    }

    var isNewChat: Bool { sessionID == nil }

    private var historyTask: Task<Void, Never>?
    private var historyLoaded = false

    /// Loads history once, in a Task owned by the view model — NOT a SwiftUI
    /// `.task`, which gets cancelled when the detail view re-lays-out during
    /// navigation (that was why messages showed up empty when opening a chat).
    func loadHistoryIfNeeded() {
        guard sessionID != nil, !historyLoaded, historyTask == nil else { return }
        runHistoryLoad()
    }

    /// Force a reload (pull-to-refresh).
    func reloadHistory() async {
        historyTask?.cancel()
        historyLoaded = false
        runHistoryLoad()
        await historyTask?.value
    }

    private func runHistoryLoad() {
        guard let id = sessionID else { return }
        isLoadingHistory = true
        historyTask = Task { @MainActor in
            defer { self.isLoadingHistory = false; self.historyTask = nil }
            do {
                let detail = try await self.api.history(id)
                self.messages = detail.messages
                if let m = detail.model { self.resolvedModel = m.split(separator: "/").last.map(String.init) }
                self.historyLoaded = true
            } catch is CancellationError {
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentIDs = pendingAttachments.map(\.id)
        guard !text.isEmpty || !attachmentIDs.isEmpty, !isStreaming else { return }
        input = ""
        error = nil
        toolStatus = nil
        notices = []

        messages.append(Message(role: .user, content: text,
                                timestamp: Date().timeIntervalSince1970,
                                attachments: attachmentIDs))
        pendingAttachments = []
        // Placeholder assistant bubble we stream into.
        let assistant = Message(role: .assistant, content: "")
        messages.append(assistant)
        isStreaming = true

        streamTask = Task { await runStream(text: text, assistantID: assistant.id, attachmentIDs: attachmentIDs) }
    }

    func addImages(_ files: [(data: Data, filename: String, mime: String)]) async {
        guard !files.isEmpty else { return }
        uploading = true; defer { uploading = false }
        // `sessionID` is nil on a brand-new chat (the session only materializes on
        // send) — the server treats that as unattributed, same as before.
        do { pendingAttachments.append(contentsOf: try await api.upload(files, sessionID: sessionID)) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func removePending(_ f: UploadedFile) { pendingAttachments.removeAll { $0.id == f.id } }

    func attachmentURL(_ id: String) -> URL? { api.attachmentURL(id) }

    private func runStream(text: String, assistantID: String, attachmentIDs: [String]) async {
        do {
            let sid = try await ensureSession(firstMessage: text.isEmpty ? "Imagem" : text)
            let opts = ChatStreamOptions(mode: agentMode ? "agent" : "chat",
                                         webSearch: webSearch, research: research,
                                         attachmentIDs: attachmentIDs)
            var sawAnyText = false

            for try await update in stream.send(message: text, sessionID: sid, options: opts) {
                switch update {
                case .textDelta(let d):
                    sawAnyText = true
                    toolStatus = nil
                    appendToAssistant(assistantID, text: d)
                case .thinkingDelta(let d):
                    appendToAssistant(assistantID, thinking: d)
                case .toolStart(let name):
                    toolStatus = friendlyTool(name)
                case .modelResolved(let m):
                    resolvedModel = m.split(separator: "/").last.map(String.init)
                case .notice(let n):
                    if !notices.contains(n) { notices.append(n) }
                case .error(let msg):
                    setAssistant(assistantID, content: msg)
                case .done:
                    break
                }
            }
            if !sawAnyText, let i = index(of: assistantID), messages[i].content.isEmpty {
                messages[i].content = "_(sem resposta)_"
            }
        } catch is CancellationError {
            // user stopped — keep whatever streamed so far
        } catch let e as APIError {
            handleStreamError(e, assistantID: assistantID)
        } catch {
            handleStreamError(.transport(error.localizedDescription), assistantID: assistantID)
        }
        isStreaming = false
        toolStatus = nil
    }

    /// Materializes a session if this is a brand-new chat.
    private func ensureSession(firstMessage: String) async throws -> String {
        if let id = sessionID { return id }
        let dc = try await api.defaultChat()
        let name = String(firstMessage.prefix(40))
        let id = try await api.createSession(from: dc, name: name.isEmpty ? "Nova conversa" : name)
        sessionID = id
        title = name.isEmpty ? "Nova conversa" : name
        resolvedModel = dc.model.split(separator: "/").last.map(String.init)
        onSessionCreated?(id)
        return id
    }

    func stop() {
        streamTask?.cancel()
        if let id = sessionID { Task { await api.stop(id) } }
        isStreaming = false
        toolStatus = nil
    }

    // MARK: - Mutation helpers

    private func index(of id: String) -> Int? { messages.firstIndex { $0.id == id } }

    private func appendToAssistant(_ id: String, text: String) {
        guard let i = index(of: id) else { return }
        messages[i].content += text
    }

    private func appendToAssistant(_ id: String, thinking: String) {
        guard let i = index(of: id) else { return }
        messages[i].thinking = (messages[i].thinking ?? "") + thinking
    }

    private func setAssistant(_ id: String, content: String) {
        guard let i = index(of: id) else { return }
        messages[i].content = content
    }

    private func handleStreamError(_ e: APIError, assistantID: String) {
        let msg = e.errorDescription ?? "Erro ao gerar resposta"
        if let i = index(of: assistantID), messages[i].content.isEmpty {
            messages[i].content = "⚠️ \(msg)"
        } else {
            error = msg
        }
    }

    private func friendlyTool(_ name: String) -> String {
        let map: [String: String] = [
            "web_search": "Pesquisando na web",
            "bash": "Executando", "python": "Executando",
            "create_document": "Escrevendo", "update_document": "Escrevendo",
            "read_document": "Lendo", "image_gen": "Gerando imagem",
            "generate_image": "Gerando imagem", "deep_research": "Pesquisando a fundo",
            "search_memory": "Lembrando", "save_memory": "Memorizando",
        ]
        let lower = name.lowercased()
        if let m = map[lower] { return m }
        for (k, v) in map where lower.contains(k) { return v }
        return "Pensando"
    }
}
