import SwiftUI

@MainActor
final class EmailViewModel: ObservableObject {
    @Published var emails: [EmailMessage] = []
    @Published var loading = false
    @Published var notConfigured = false
    @Published var error: String?

    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func load() async {
        loading = true; defer { loading = false }
        do {
            let resp = try await api.emailList()
            emails = resp.emails
            // Server reports a backend error when no mail account is connected.
            notConfigured = resp.emails.isEmpty && (resp.error?.isEmpty == false)
            error = nil
        } catch is CancellationError {
            // view transition tore down the load — ignore
        } catch {
            self.error = msg(error)
        }
    }

    func read(_ m: EmailMessage) async -> EmailDetail? {
        let detail = try? await api.emailRead(m.uid)
        if let i = emails.firstIndex(where: { $0.uid == m.uid }), !emails[i].isRead {
            emails[i].isRead = true
            await api.emailMarkRead(m.uid)
        }
        return detail
    }

    func archive(_ m: EmailMessage) async {
        do { try await api.emailArchive(m.uid); emails.removeAll { $0.uid == m.uid } }
        catch { self.error = msg(error) }
    }

    func delete(_ m: EmailMessage) async {
        do { try await api.emailDelete(m.uid); emails.removeAll { $0.uid == m.uid } }
        catch { self.error = msg(error) }
    }

    private func msg(_ e: Error) -> String {
        (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
    }
}

struct EmailView: View {
    let app: AppState
    @StateObject private var vm: EmailViewModel
    @Environment(\.theme) private var theme
    @State private var opened: EmailMessage?
    @State private var showAccounts = false
    @State private var showHelp = false

    init(app: AppState) {
        self.app = app
        _vm = StateObject(wrappedValue: EmailViewModel(api: app.api))
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            content
        }
        .screenChrome(title: "Email") {
        } trailing: {
            Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }
            Button { showAccounts = true } label: { Image(systemName: "person.crop.circle") }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(item: $opened) { m in
            EmailReader(message: m, vm: vm)
        }
        .sheet(isPresented: $showAccounts) {
            EmailAccountsView(app: app) { Task { await vm.load() } }
        }
        .sheet(isPresented: $showHelp) { EmailLoginHelpView() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.emails.isEmpty && vm.loading {
            VStack(spacing: 10) {
                ProgressView().tint(theme.accent)
                Text("Carregando a caixa…").font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
            }
        } else if vm.emails.isEmpty, let err = vm.error {
            VStack(spacing: 14) {
                stateView(icon: "exclamationmark.triangle",
                          title: "Não consegui carregar o email",
                          subtitle: err)
                Text("Provedores como o iCloud exigem uma senha de app (não a senha do Apple ID).")
                    .font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
                Button { showHelp = true } label: {
                    Label("Como conectar (passo a passo)", systemImage: "questionmark.circle")
                        .font(.ody(.subheadline, design: .monospaced))
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(theme.accent, in: Capsule()).foregroundStyle(.white)
                }.buttonStyle(.plain)
                HStack(spacing: 10) {
                    Button { Task { await vm.load() } } label: {
                        Label("Tentar de novo", systemImage: "arrow.clockwise")
                            .font(.ody(.subheadline, design: .monospaced))
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .overlay(Capsule().stroke(theme.border, lineWidth: 1)).foregroundStyle(theme.fg)
                    }.buttonStyle(.plain)
                    Button { showAccounts = true } label: {
                        Label("Contas", systemImage: "person.crop.circle")
                            .font(.ody(.subheadline, design: .monospaced))
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .overlay(Capsule().stroke(theme.border, lineWidth: 1))
                            .foregroundStyle(theme.fg)
                    }.buttonStyle(.plain)
                }
            }
        } else if vm.notConfigured {
            VStack(spacing: 16) {
                stateView(icon: "envelope.badge.shield.half.filled",
                          title: "Email não configurado",
                          subtitle: "Conecte uma conta IMAP para ver sua caixa aqui.")
                Button { showAccounts = true } label: {
                    Label("Conectar conta", systemImage: "plus")
                        .font(.ody(.subheadline, design: .monospaced))
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(theme.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        } else if vm.emails.isEmpty {
            stateView(icon: "tray", title: "Caixa vazia", subtitle: "Nenhuma mensagem na INBOX.")
        } else {
            List {
                ForEach(vm.emails) { m in
                    row(m).listRowBackground(theme.bg)
                        .onTapGesture { opened = m }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { Task { await vm.delete(m) } } label: {
                                Label("Apagar", systemImage: "trash")
                            }
                            Button { Task { await vm.archive(m) } } label: {
                                Label("Arquivar", systemImage: "archivebox")
                            }.tint(theme.border)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ m: EmailMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(m.isRead ? Color.clear : theme.accent)
                .frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(m.displayFrom)
                        .font(.ody(.subheadline, design: .monospaced).weight(m.isRead ? .regular : .semibold))
                        .foregroundStyle(theme.fg).lineLimit(1)
                    Spacer()
                    if m.hasAttachments { Image(systemName: "paperclip").font(.caption2).foregroundStyle(theme.secondaryText) }
                }
                Text(m.subject)
                    .font(.ody(size: 13, design: .monospaced))
                    .foregroundStyle(m.isRead ? theme.secondaryText : theme.fg)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func stateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.ody(size: 44)).foregroundStyle(theme.accent)
            Text(LocalizedStringKey(title)).font(.ody(.headline, design: .monospaced)).foregroundStyle(theme.fg)
            Text(LocalizedStringKey(subtitle))
                .font(.ody(.footnote, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

struct EmailReader: View {
    let message: EmailMessage
    @ObservedObject var vm: EmailViewModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var detail: EmailDetail?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ZStack {
                theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(detail?.subject ?? message.subject)
                            .font(.ody(.title3, design: .monospaced).weight(.semibold))
                            .foregroundStyle(theme.fg)
                        HStack {
                            Text(message.displayFrom)
                                .font(.ody(size: 12, design: .monospaced))
                                .foregroundStyle(theme.secondaryText)
                            Spacer()
                            if let d = message.date {
                                Text(d).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText)
                            }
                        }
                        Divider().overlay(theme.border)
                        if loading {
                            ProgressView().tint(theme.accent).frame(maxWidth: .infinity).padding(.top, 30)
                        } else {
                            Text(detail?.body ?? "(sem conteúdo)")
                                .font(.ody(.body, design: .monospaced))
                                .foregroundStyle(theme.fg)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { dismiss() } } }
        }
        .tint(theme.accent)
        .task {
            detail = await vm.read(message)
            loading = false
        }
    }
}
