import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Turn two-factor authentication on or off for the signed-in account.
///
/// 1.8 showed 2FA as a read-only badge in two places and could change it in
/// neither — the app only had `GET /2fa/status`. The server's three writes
/// (`setup` → QR + secret, `confirm` → backup codes, `disable` ← password)
/// are ordinary user routes, not admin ones.
@MainActor final class TwoFactorVM: ObservableObject {
    enum Step { case unknown, off, enrolling, backupCodes, on }
    @Published var step: Step = .unknown
    @Published var secret = ""
    @Published var qr: Data?
    @Published var code = ""
    @Published var backupCodes: [String] = []
    @Published var password = ""
    @Published var note: String?
    @Published var busy = false
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func load() async {
        if let on = try? await api.twoFAEnabled() { step = on ? .on : .off }
    }

    func begin() async {
        busy = true; note = nil; defer { busy = false }
        do {
            let s = try await api.twoFASetup()
            secret = s.secret; qr = s.qrPNG; code = ""
            step = .enrolling
        } catch { note = SettingsUI.failure(error, "Falha: %@") }
    }

    func confirm() async {
        busy = true; note = nil; defer { busy = false }
        do {
            backupCodes = try await api.twoFAConfirm(code: code.trimmingCharacters(in: .whitespaces))
            step = .backupCodes
        } catch { note = SettingsUI.failure(error, "Falha: %@") }
    }

    func disable() async {
        busy = true; note = nil; defer { busy = false }
        do {
            try await api.twoFADisable(password: password)
            password = ""
            step = .off
        } catch { note = SettingsUI.failure(error, "Falha: %@") }
    }
}

struct TwoFactorView: View {
    @StateObject private var vm: TwoFactorVM
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    /// Called when the sheet closes so the Conta row can show the new state.
    var onChange: (Bool) -> Void

    init(app: AppState, onChange: @escaping (Bool) -> Void) {
        _vm = StateObject(wrappedValue: TwoFactorVM(api: app.api))
        self.onChange = onChange
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let n = vm.note {
                        Text(LocalizedStringKey(n)).font(.ody(size: 11)).foregroundStyle(theme.danger)
                    }
                    switch vm.step {
                    case .unknown: ProgressView().tint(theme.accent)
                    case .off: offCard
                    case .enrolling: enrollCard
                    case .backupCodes: backupCard
                    case .on: onCard
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("2FA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { close() } } }
            .themedNavBar(theme)
        }
        .tint(theme.accent)
        .task { await vm.load() }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    private func close() {
        onChange(vm.step == .on || vm.step == .backupCodes)
        dismiss()
    }

    // MARK: - Cards

    private var offCard: some View {
        SettingsCard {
            Text("Desativado").font(.ody(.subheadline)).foregroundStyle(theme.secondaryText)
            Button { Task { await vm.begin() } } label: { Label("Ativar 2FA", systemImage: "lock.shield") }
                .buttonStyle(.plain).foregroundStyle(theme.accent).font(.ody(.subheadline))
                .disabled(vm.busy)
        }
    }

    private var enrollCard: some View {
        SettingsCard {
            Text("Escaneie o QR no app autenticador ou digite o segredo.")
                .font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let png = vm.qr, let img = platformImage(png) {
                img.resizable().interpolation(.none).scaledToFit()
                    .frame(width: 200, height: 200)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 8) {
                Text(vm.secret).font(.ody(size: 12).monospaced()).foregroundStyle(theme.fg)
                    .textSelection(.enabled).lineLimit(2)
                Spacer()
                Button { copy(vm.secret) } label: { Label(copied ? "Copiado" : "Copiar", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.plain).font(.ody(size: 11)).foregroundStyle(theme.accent)
            }
            SettingsUI.field("Código de 6 dígitos", $vm.code, placeholder: "123456", theme: theme, numeric: true)
            HStack {
                Button("Confirmar") { Task { await vm.confirm() } }
                    .buttonStyle(.plain).foregroundStyle(theme.accent).font(.ody(.subheadline))
                    .disabled(vm.busy || vm.code.trimmingCharacters(in: .whitespaces).count < 6)
                Spacer()
                Button("Cancelar") { vm.step = .off }
                    .buttonStyle(.plain).foregroundStyle(theme.secondaryText).font(.ody(.subheadline))
            }
        }
    }

    private var backupCard: some View {
        SettingsCard {
            Label("Ativado", systemImage: "checkmark.shield.fill").foregroundStyle(theme.green).font(.ody(.subheadline))
            Text("Códigos de backup").font(.ody(.subheadline, weight: .semibold)).foregroundStyle(theme.fg)
            Text("Guarde estes códigos — cada um funciona uma vez.")
                .font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(vm.backupCodes, id: \.self) { c in
                Text(c).font(.ody(size: 13).monospaced()).foregroundStyle(theme.fg).textSelection(.enabled)
            }
            Button { copy(vm.backupCodes.joined(separator: "\n")) } label: {
                Label(copied ? "Copiado" : "Copiar", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.plain).font(.ody(size: 11)).foregroundStyle(theme.accent)
        }
    }

    private var onCard: some View {
        SettingsCard {
            Label("Ativado", systemImage: "checkmark.shield.fill").foregroundStyle(theme.green).font(.ody(.subheadline))
            SettingsUI.field("Senha atual", $vm.password, placeholder: "••••••••", theme: theme, secure: true)
            Button(role: .destructive) { Task { await vm.disable() } } label: { Label("Desativar 2FA", systemImage: "lock.open") }
                .buttonStyle(.plain).foregroundStyle(theme.danger).font(.ody(.subheadline))
                .disabled(vm.busy || vm.password.isEmpty)
        }
    }

    // MARK: - Platform bits

    private func platformImage(_ data: Data) -> Image? {
        #if os(macOS)
        NSImage(data: data).map { Image(nsImage: $0) }
        #else
        UIImage(data: data).map { Image(uiImage: $0) }
        #endif
    }

    private func copy(_ s: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #else
        UIPasteboard.general.string = s
        #endif
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
