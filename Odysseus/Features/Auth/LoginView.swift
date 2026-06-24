import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.theme) private var theme

    @State private var username = ""
    @State private var password = ""
    @State private var totp = ""
    @State private var remember = true
    @State private var showServerSheet = false
    @FocusState private var focus: Field?

    enum Field { case user, pass, totp }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            BackgroundDots().opacity(0.5)

            VStack(spacing: 22) {
                Spacer(minLength: 40)
                VStack(spacing: 10) {
                    BrandMark(size: 64)
                    Text("Odysseus")
                        .font(.ody(.largeTitle, design: .monospaced).weight(.semibold))
                        .foregroundStyle(theme.fg)
                    Text(serverLabel)
                        .font(.ody(.footnote, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                        .onTapGesture { showServerSheet = true }
                }

                VStack(spacing: 14) {
                    field(title: "Username", text: $username, field: .user)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .onSubmit { focus = .pass }

                    secureField(title: "Password", text: $password, field: .pass)
                        .submitLabel(app.totpRequired ? .next : .go)
                        .onSubmit { app.totpRequired ? (focus = .totp) : submit() }

                    if app.totpRequired {
                        field(title: "Código 2FA", text: $totp, field: .totp)
                            .keyboardType(.numberPad)
                            .submitLabel(.go)
                            .onSubmit(submit)
                            .transition(.opacity)
                    }

                    Toggle(isOn: $remember) {
                        Text("Manter conectado")
                            .font(.ody(.subheadline, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .tint(theme.accent)
                }
                .padding(.horizontal, 4)

                if let err = app.loginError {
                    Text(err)
                        .font(.ody(.footnote, design: .monospaced))
                        .foregroundStyle(theme.accent)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: submit) {
                    HStack {
                        if app.loggingIn { ProgressView().tint(.white) }
                        Text(app.totpRequired ? "Verificar" : "Entrar")
                            .font(.ody(.headline, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .disabled(app.loggingIn || username.isEmpty || password.isEmpty)
                .opacity(app.loggingIn || username.isEmpty || password.isEmpty ? 0.6 : 1)

                Spacer()
            }
            .frame(maxWidth: 420)
            .padding(24)
        }
        .animation(.easeInOut(duration: 0.2), value: app.totpRequired)
        .sheet(isPresented: $showServerSheet) { ServerSheet() }
        .onAppear { if username.isEmpty { username = Keychain.get(Keychain.usernameKey) ?? "" } }
    }

    private var serverLabel: String {
        let url = app.serverConfig.baseURL
        // Only show the port when it's explicit (e.g. the LAN ":7000"); for plain
        // http/https the scheme's default port is implied, so don't print a
        // misleading ":80"/":443".
        let label = url.host.map { host in
            url.port.map { "\(host):\($0)" } ?? host
        } ?? url.absoluteString
        return label + "  ›"
    }

    private func submit() {
        focus = nil
        Task {
            await app.login(username: username.trimmingCharacters(in: .whitespaces),
                            password: password,
                            remember: remember,
                            totp: app.totpRequired ? totp : nil)
        }
    }

    @ViewBuilder
    private func field(title: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.ody(.caption, design: .monospaced)).foregroundStyle(theme.secondaryText)
            TextField("", text: text)
                .focused($focus, equals: field)
                .styledInput(theme)
        }
    }

    @ViewBuilder
    private func secureField(title: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.ody(.caption, design: .monospaced)).foregroundStyle(theme.secondaryText)
            SecureField("", text: text)
                .textContentType(.password)
                .focused($focus, equals: field)
                .styledInput(theme)
        }
    }
}

private extension View {
    func styledInput(_ theme: Theme) -> some View {
        self
            .font(.ody(.body, design: .monospaced))
            .foregroundStyle(theme.fg)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1))
    }
}

/// Subtle dotted background matching the web login's "dots" pattern.
struct BackgroundDots: View {
    @Environment(\.theme) private var theme
    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 20
            Canvas { ctx, size in
                let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1.6, height: 1.6))
                ctx.translateBy(x: 0, y: 0)
                var y: CGFloat = 0
                while y < size.height {
                    var x: CGFloat = 0
                    while x < size.width {
                        var c = ctx
                        c.translateBy(x: x, y: y)
                        c.fill(dot, with: .color(theme.fg.opacity(0.08)))
                        x += spacing
                    }
                    y += spacing
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
