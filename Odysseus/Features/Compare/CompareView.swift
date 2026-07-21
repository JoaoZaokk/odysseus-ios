import SwiftUI
import MarkdownUI

/// One turn in a comparison column.
struct CompareTurn: Identifiable {
    let id = UUID()
    let role: Role
    var text: String
    enum Role { case user, assistant }
}

@MainActor
final class CompareViewModel: ObservableObject {
    @Published var models: [ChatModel] = []
    @Published var modelA: ChatModel?
    @Published var modelB: ChatModel?
    @Published var prompt = ""
    @Published var turnsA: [CompareTurn] = []
    @Published var turnsB: [CompareTurn] = []
    @Published var streaming = false
    @Published var error: String?

    private let api: APIClient
    private let stream: ChatStreamClient
    private var sessionA: String?
    private var sessionB: String?
    private var lastA: ChatModel?
    private var lastB: ChatModel?

    init(api: APIClient, stream: ChatStreamClient) {
        self.api = api; self.stream = stream
    }

    func load() async {
        do {
            models = try await api.models()
            if modelA == nil { modelA = models.first }
            if modelB == nil { modelB = models.count > 1 ? models[1] : models.first }
        } catch is CancellationError {} catch { self.error = msg(error) }
    }

    var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !streaming && modelA != nil && modelB != nil
    }

    func send() {
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !streaming, let a = modelA, let b = modelB else { return }
        error = nil
        streaming = true
        turnsA.append(CompareTurn(role: .user, text: p))
        turnsB.append(CompareTurn(role: .user, text: p))
        prompt = ""
        Task {
            async let ra: Void = run(model: a, prompt: p, isA: true)
            async let rb: Void = run(model: b, prompt: p, isA: false)
            _ = await (ra, rb)
            streaming = false
        }
    }

    func reset() {
        turnsA = []; turnsB = []
        sessionA = nil; sessionB = nil; lastA = nil; lastB = nil
    }

    private func run(model: ChatModel, prompt: String, isA: Bool) async {
        if isA { turnsA.append(CompareTurn(role: .assistant, text: "")) }
        else { turnsB.append(CompareTurn(role: .assistant, text: "")) }
        do {
            let sid = try await ensureSession(model: model, isA: isA)
            for try await update in stream.send(message: prompt, sessionID: sid, options: ChatStreamOptions()) {
                switch update {
                case .textDelta(let d): appendDelta(d, isA: isA)
                case .error(let m): appendDelta("\n⚠️ \(m)", isA: isA)
                default: break
                }
            }
        } catch is CancellationError {
        } catch { appendDelta("\n⚠️ \(msg(error))", isA: isA) }
    }

    private func appendDelta(_ d: String, isA: Bool) {
        if isA { if !turnsA.isEmpty { turnsA[turnsA.count - 1].text += d } }
        else { if !turnsB.isEmpty { turnsB[turnsB.count - 1].text += d } }
    }

    /// Creates (or reuses) a session per column. Recreated when the model changes.
    private func ensureSession(model: ChatModel, isA: Bool) async throws -> String {
        let existing = isA ? sessionA : sessionB
        let last = isA ? lastA : lastB
        if let existing, last == model { return existing }
        let dc = DefaultChat(endpointURL: model.endpointURL ?? "", model: model.id, endpointID: model.endpointId)
        let sid = try await api.createSession(from: dc, name: "⚖︎ Compare: \(model.name)")
        if isA { sessionA = sid; lastA = model } else { sessionB = sid; lastB = model }
        return sid
    }

    private func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? e.localizedDescription }
}

struct CompareView: View {
    @StateObject private var vm: CompareViewModel
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool

    init(app: AppState) {
        _vm = StateObject(wrappedValue: CompareViewModel(api: app.api, stream: app.stream))
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    column(title: "A", model: $vm.modelA, turns: vm.turnsA)
                    Divider().overlay(theme.border)
                    column(title: "B", model: $vm.modelB, turns: vm.turnsB)
                }
                composer
            }
        }
        .screenChrome(title: "Comparar") {
        } trailing: {
            Button { vm.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                .disabled(vm.streaming || (vm.turnsA.isEmpty && vm.turnsB.isEmpty))
        }
        .task { await vm.load() }
    }

    private func column(title: String, model: Binding<ChatModel?>, turns: [CompareTurn]) -> some View {
        VStack(spacing: 6) {
            Menu {
                ForEach(vm.models.filter { !$0.isExtra }) { m in
                    Button(m.name) { model.wrappedValue = m }
                }
                // Non-curated rest (`models_extra`) — only newer servers send
                // it, so on an older server this submenu simply never appears.
                let extras = vm.models.filter(\.isExtra)
                if !extras.isEmpty {
                    Menu("Mais modelos") {
                        ForEach(extras) { m in
                            Button(m.name) { model.wrappedValue = m }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(model.wrappedValue?.name ?? "Modelo \(title)")
                        .font(.ody(size: 11, design: .monospaced)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.ody(size: 8))
                }
                .foregroundStyle(theme.fg)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 8).padding(.top, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if turns.isEmpty {
                            Text("Envie a mesma pergunta para os dois modelos.")
                                .font(.ody(size: 11, design: .monospaced))
                                .foregroundStyle(theme.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }
                        ForEach(turns) { turn in bubble(turn).id(turn.id) }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 10).padding(.bottom, 10)
                }
                .onChange(of: turns.last?.text) { _, _ in
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func bubble(_ turn: CompareTurn) -> some View {
        if turn.role == .user {
            HStack {
                Spacer(minLength: 24)
                Text(turn.text)
                    .font(.ody(size: 12, design: .monospaced))
                    .foregroundStyle(theme.fg)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(theme.userBubble, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1))
            }
        } else {
            HStack {
                Markdown(turn.text.isEmpty ? "_…_" : turn.text)
                    .markdownTextStyle { ForegroundColor(theme.fg) }
                    .font(.ody(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(theme.aiBubble, in: RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 0)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Mesma pergunta para os dois…", text: $vm.prompt)
                .textFieldStyle(.plain)
                .font(.ody(.subheadline, design: .monospaced))
                .foregroundStyle(theme.fg)
                .focused($focused)
                .onSubmit { vm.send() }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.border, lineWidth: 1))
            Button {
                focused = false; vm.send()
            } label: {
                Image(systemName: vm.streaming ? "ellipsis" : "arrow.up")
                    .font(.ody(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(vm.canSend || vm.streaming ? theme.accent : theme.border, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!vm.canSend)
        }
        .padding(12)
        .background(theme.bg)
    }
}
