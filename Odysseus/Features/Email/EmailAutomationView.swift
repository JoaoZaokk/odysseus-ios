import SwiftUI

/// Email automation, per account: the away auto-reply, newsletter cleanup
/// and the writing style the AI uses for drafted replies. Every route here is
/// an ordinary user route scoped by `account_id` — nothing is admin-gated.
@MainActor final class EmailAutomationVM: ObservableObject {
    @Published var accounts: [EmailAccount] = []
    @Published var accountId = ""
    @Published var cfg = EmailAutomationConfig()
    @Published var style = ""
    @Published var candidates: [UnsubscribeCandidate] = []
    @Published var selected: Set<String> = []
    @Published var scanInfo: String?
    @Published var note: String?
    @Published var noteIsFailure = false
    @Published var styleNote: String?
    @Published var loading = false
    @Published var scanning = false
    @Published var extracting = false
    @Published var saving = false
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    static let cooldowns: [(id: String, label: String)] = [
        ("period", "Uma vez enquanto estiver ativa"), ("1d", "A cada dia"), ("3d", "A cada 3 dias"), ("7d", "A cada 7 dias"),
    ]

    func load() async {
        loading = true; defer { loading = false }
        accounts = (try? await api.emailAccounts()) ?? []
        if accountId.isEmpty { accountId = accounts.first { $0.isDefault }?.id ?? accounts.first?.id ?? "" }
        await reload()
    }

    func reload() async {
        candidates = []; selected = []; scanInfo = nil
        do {
            cfg = try await api.emailAutomationConfig(accountId: accountId)
            style = try await api.emailWritingStyle(accountId: accountId)
        } catch { fail(SettingsUI.failure(error, "Falha ao carregar automações: %@")) }
    }

    func save() async {
        saving = true; defer { saving = false }
        do { try await api.saveEmailAutomationConfig(cfg, accountId: accountId); ok("Salvo.") }
        catch { fail(SettingsUI.failure(error, "Falha ao salvar: %@")) }
    }

    func saveStyle() async {
        do { try await api.saveEmailWritingStyle(style, accountId: accountId); styleNote = "Estilo salvo." }
        catch { styleNote = SettingsUI.failure(error, "Falha ao salvar: %@") }
    }

    func extractStyle() async {
        extracting = true; defer { extracting = false }
        styleNote = nil
        do { style = try await api.extractEmailWritingStyle(accountId: accountId); styleNote = "Estilo extraído." }
        catch { styleNote = SettingsUI.failure(error, "Falha ao extrair estilo: %@") }
    }

    func scan() async {
        scanning = true; defer { scanning = false }
        selected = []
        do {
            let r = try await api.unsubscribeScan(accountId: accountId)
            candidates = r.candidates
            scanInfo = r.candidates.isEmpty ? L("Nenhum candidato encontrado.")
                                            : L("%lld candidatos em %lld emails.", r.total, r.scanned)
        } catch { fail(SettingsUI.failure(error, "Falha ao buscar candidatos: %@")) }
    }

    func unsubscribe(_ c: UnsubscribeCandidate) async {
        do {
            try await api.unsubscribeExecute(uid: c.id, folder: c.folder, accountId: accountId)
            candidates.removeAll { $0.id == c.id }
            ok("Descadastramento enviado.")
        } catch { fail(SettingsUI.failure(error, "Falha ao descadastrar: %@")) }
    }

    func cleanup(_ action: String) async {
        let uids = candidates.filter { selected.contains($0.id) }.flatMap { [$0.id] + $0.duplicateUids }
        guard !uids.isEmpty else { return }
        do {
            let r = try await api.unsubscribeCleanup(uids: uids, action: action, accountId: accountId)
            candidates.removeAll { selected.contains($0.id) }
            selected = []
            ok(L("%lld movidos, %lld falharam.", r.changed, r.failed))
        } catch { fail(SettingsUI.failure(error, "Falha na limpeza: %@")) }
    }

    private func ok(_ s: String) { note = s; noteIsFailure = false }
    private func fail(_ s: String?) { note = s; noteIsFailure = true }
}

struct EmailAutomationView: View {
    @StateObject private var vm: EmailAutomationVM
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var confirmUnsub: UnsubscribeCandidate?
    @State private var confirmCleanup: String?
    init(app: AppState) { _vm = StateObject(wrappedValue: EmailAutomationVM(api: app.api)) }

    private var accountName: String {
        vm.accounts.first { $0.id == vm.accountId }.map { $0.name.isEmpty ? $0.fromAddress : $0.name } ?? "—"
    }

    var body: some View {
        NavigationStack {
            SettingsScroll("Automação de email", subtitle: "Resposta automática, limpeza de newsletters e estilo de escrita.") {
                if vm.accounts.isEmpty && !vm.loading {
                    Text("Nenhuma conta de email conectada.").font(.ody(size: 12)).foregroundStyle(theme.secondaryText)
                } else {
                    if vm.accounts.count > 1 {
                        SettingsUI.menuRow("Conta", value: accountName,
                                           options: vm.accounts.map { (id: $0.id, label: $0.name.isEmpty ? $0.fromAddress : $0.name) },
                                           theme: theme) { vm.accountId = $0; Task { await vm.reload() } }
                    }
                    if let n = vm.note {
                        Text(LocalizedStringKey(n)).font(.ody(size: 11)).foregroundStyle(vm.noteIsFailure ? theme.danger : theme.green)
                    }
                    autoReplyCard
                    cleanupCard
                    styleCard
                }
            }
            .navigationTitle("Automação de email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .themedNavBar(theme)
        }
        .tint(theme.accent)
        .task { await vm.load() }
        .alert(confirmUnsub.map { L("Descadastrar de %@?", $0.fromAddress) } ?? "",
               isPresented: Binding(get: { confirmUnsub != nil }, set: { if !$0 { confirmUnsub = nil } })) {
            Button("Descadastrar") { if let c = confirmUnsub { Task { await vm.unsubscribe(c) } }; confirmUnsub = nil }
            Button("Cancelar", role: .cancel) { confirmUnsub = nil }
        }
        .alert(confirmCleanup == "delete" ? L("Excluir %lld emails?", vm.selected.count) : L("Mover %lld emails para o spam?", vm.selected.count),
               isPresented: Binding(get: { confirmCleanup != nil }, set: { if !$0 { confirmCleanup = nil } })) {
            Button(confirmCleanup == "delete" ? "Excluir" : "Mover para spam", role: .destructive) {
                if let a = confirmCleanup { Task { await vm.cleanup(a) } }; confirmCleanup = nil
            }
            Button("Cancelar", role: .cancel) { confirmCleanup = nil }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
        #endif
    }

    private var autoReplyCard: some View {
        SettingsCard {
            HStack {
                Text("Resposta automática").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
                Spacer()
                Toggle("", isOn: $vm.cfg.enabled).labelsHidden().tint(theme.accent)
            }
            Text("Respostas de ausência para os emails recebidos desta conta.")
                .font(.ody(size: 10)).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            if vm.cfg.enabled {
                HStack(spacing: 10) {
                    SettingsUI.field("Data de início", $vm.cfg.start, placeholder: "2026-09-08", theme: theme)
                    SettingsUI.field("Data de término", $vm.cfg.end, placeholder: "2026-09-15", theme: theme)
                }
                SettingsUI.field("Assunto", $vm.cfg.subject, placeholder: "(Away) {subject}", theme: theme)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mensagem").font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                    TextEditor(text: $vm.cfg.message)
                        .font(.ody(.subheadline)).foregroundStyle(theme.fg)
                        .scrollContentBackground(.hidden).frame(minHeight: 80)
                        .padding(6).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                }
                SettingsUI.menuRow("Enviar ao mesmo remetente",
                                   value: EmailAutomationVM.cooldowns.first { $0.id == vm.cfg.cooldown }?.label ?? vm.cfg.cooldown,
                                   options: EmailAutomationVM.cooldowns, theme: theme) { vm.cfg.cooldown = $0 }
                Toggle(isOn: $vm.cfg.excludeAutomated) {
                    Text("Ignorar remetentes automáticos e no-reply").font(.ody(.subheadline)).foregroundStyle(theme.fg)
                }.tint(theme.accent)
                Toggle(isOn: $vm.cfg.pauseNotifications) {
                    Text("Pausar notificações de email enquanto estiver ativa").font(.ody(.subheadline)).foregroundStyle(theme.fg)
                }.tint(theme.accent)
            }
            HStack {
                Text("Vale só para esta conta.").font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
                Spacer()
                if vm.saving { ProgressView().controlSize(.small) }
                else { SettingsUI.saveButton(theme: theme) { Task { await vm.save() } } }
            }
        }
    }

    private var cleanupCard: some View {
        SettingsCard {
            Text("Limpeza de newsletters").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
            Text("Encontre newsletters e anúncios com opção de descadastro.")
                .font(.ody(size: 10)).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(vm.scanning ? "Procurando…" : "Procurar") { Task { await vm.scan() } }
                    .buttonStyle(.plain).foregroundStyle(theme.accent).font(.ody(size: 12)).disabled(vm.scanning)
                Spacer()
                if let s = vm.scanInfo { Text(LocalizedStringKey(s)).font(.ody(size: 10)).foregroundStyle(theme.secondaryText) }
            }
            ForEach(vm.candidates) { c in
                Rectangle().fill(theme.border).frame(height: 1)
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        if vm.selected.contains(c.id) { vm.selected.remove(c.id) } else { vm.selected.insert(c.id) }
                    } label: {
                        Image(systemName: vm.selected.contains(c.id) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(vm.selected.contains(c.id) ? theme.accent : theme.secondaryText)
                    }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.fromName.isEmpty ? c.fromAddress : c.fromName).font(.ody(size: 12)).foregroundStyle(theme.fg).lineLimit(1)
                        Text(c.subject).font(.ody(size: 10)).foregroundStyle(theme.secondaryText).lineLimit(1)
                        if c.duplicateCount > 0 {
                            Text(L("%lld repetidos", c.duplicateCount)).font(.ody(size: 9)).foregroundStyle(theme.secondaryText)
                        }
                    }
                    Spacer()
                    if c.canExecute {
                        Button("Descadastrar") { confirmUnsub = c }
                            .buttonStyle(.plain).foregroundStyle(theme.accent).font(.ody(size: 11))
                    } else {
                        Text("Só tem link na web — abra manualmente.").font(.ody(size: 9)).foregroundStyle(theme.secondaryText)
                            .frame(maxWidth: 120, alignment: .trailing)
                    }
                }
            }
            if !vm.selected.isEmpty {
                HStack(spacing: 14) {
                    Button("Mover para spam") { confirmCleanup = "junk" }.buttonStyle(.plain).foregroundStyle(theme.warning)
                    Button("Excluir", role: .destructive) { confirmCleanup = "delete" }.buttonStyle(.plain).foregroundStyle(theme.danger)
                    Spacer()
                }
                .font(.ody(size: 12))
            }
        }
    }

    private var styleCard: some View {
        SettingsCard {
            Text("Estilo de escrita das respostas").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
            Text("Usado quando a IA escreve respostas para você.")
                .font(.ody(size: 10)).foregroundStyle(theme.secondaryText)
            TextEditor(text: $vm.style)
                .font(.ody(.subheadline)).foregroundStyle(theme.fg)
                .scrollContentBackground(.hidden).frame(minHeight: 90)
                .padding(6).background(theme.bg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
            HStack {
                Button(vm.extracting ? "Analisando emails enviados…" : "Extrair dos enviados") { Task { await vm.extractStyle() } }
                    .buttonStyle(.plain).foregroundStyle(theme.accent).font(.ody(size: 12)).disabled(vm.extracting)
                Spacer()
                SettingsUI.saveButton(theme: theme) { Task { await vm.saveStyle() } }
            }
            if let n = vm.styleNote {
                Text(LocalizedStringKey(n)).font(.ody(size: 11))
                    .foregroundStyle(n.hasPrefix("Falha") || n.hasPrefix(L("Falha")) ? theme.danger : theme.green)
            }
        }
    }
}
