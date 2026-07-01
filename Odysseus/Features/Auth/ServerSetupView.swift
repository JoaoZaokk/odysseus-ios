import SwiftUI

/// Mandatory first-run gate. Odysseus is a **client** for a self-hosted server, so
/// it can't do anything until the user points it at their own Odysseus instance.
/// Shown by `RootView` as a full-cover overlay while `!app.serverConfigured`, with
/// no way out until a valid address is saved (fixes App Review 2.1: the reviewer
/// must set a real server instead of trying to log in against the placeholder).
struct ServerSetupView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.theme) private var theme
    @State private var text = ""
    @FocusState private var focused: Bool

    private var validURL: URL? { ServerConfig.normalize(text) }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            #if os(macOS)
            VisualEffectBackground().ignoresSafeArea().opacity(0.7)
            #else
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            #endif

            ScrollView {
                VStack(spacing: 20) {
                    BrandMark(size: 72)

                    Text("Configure seu servidor")
                        .font(.ody(.title2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(theme.fg)
                        .multilineTextAlignment(.center)

                    Text("O Odysseus é um cliente do seu próprio servidor. Informe o endereço do seu servidor Odysseus para continuar.")
                        .font(.ody(.subheadline, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Endereço do servidor Odysseus")
                            .font(.ody(.caption, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                        TextField("https://odysseus.example.com", text: $text)
                            .font(.ody(.body, design: .monospaced))
                            .foregroundStyle(theme.fg)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .submitLabel(.go)
                            #endif
                            .focused($focused)
                            .onSubmit(save)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(theme.panel, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1))
                    }

                    Button(action: save) {
                        Text("Salvar")
                            .font(.ody(.headline, design: .monospaced))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(validURL == nil ? theme.panel : theme.accent,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(validURL == nil ? theme.secondaryText : .white)
                    }
                    .buttonStyle(.plain)
                    .disabled(validURL == nil)
                }
                .frame(maxWidth: 460)
                .padding(28)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { focused = true }
    }

    private func save() {
        guard let url = validURL else { return }
        app.updateServer(url)
    }
}
