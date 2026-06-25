import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Phase { case launching, login, main }

    @Published var phase: Phase = .launching
    @Published var serverConfig: ServerConfig
    @Published var features = Features()
    @Published var username: String?

    // Login flow
    @Published var loginError: String?
    @Published var loggingIn = false
    @Published var totpRequired = false

    private(set) var api: APIClient
    private(set) var stream: ChatStreamClient

    init() {
        let cfg = ServerConfig.load()
        self.serverConfig = cfg
        let client = APIClient(config: cfg)
        self.api = client
        self.stream = ChatStreamClient(api: client)
    }

    /// Called on launch: check whether the persisted session cookie is still
    /// valid; if so, go straight to the main UI, otherwise show login.
    func bootstrap() async {
        do {
            let status = try await api.status()
            if status.authenticated {
                username = status.username
                await loadFeatures()
                phase = .main
            } else {
                await tryAutoLogin()
            }
        } catch {
            // Server unreachable or not configured — fall back to login screen.
            phase = .login
        }
    }

    private func tryAutoLogin() async {
        guard let u = Keychain.get(Keychain.usernameKey),
              let p = Keychain.get(Keychain.passwordKey) else {
            phase = .login; return
        }
        do {
            let resp = try await api.login(username: u, password: p, remember: true)
            if resp.totpRequired == true { phase = .login; totpRequired = true; return }
            username = u
            await loadFeatures()
            phase = .main
        } catch {
            phase = .login
        }
    }

    func login(username u: String, password p: String, remember: Bool, totp: String?) async {
        loginError = nil; loggingIn = true
        defer { loggingIn = false }
        do {
            let resp = try await api.login(username: u, password: p, remember: remember, totp: totp)
            if resp.totpRequired == true && (totp?.isEmpty ?? true) {
                totpRequired = true
                return
            }
            if remember {
                Keychain.set(u, for: Keychain.usernameKey)
                Keychain.set(p, for: Keychain.passwordKey)
            }
            username = u
            totpRequired = false
            await loadFeatures()
            phase = .main
        } catch {
            loginError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func logout() async {
        await api.logout()
        Keychain.delete(Keychain.usernameKey)
        Keychain.delete(Keychain.passwordKey)
        username = nil
        totpRequired = false
        phase = .login
    }

    func loadFeatures() async {
        features = (try? await api.features()) ?? Features()
    }

    func updateServer(_ url: URL) {
        let changed = url != serverConfig.baseURL
        var cfg = serverConfig
        cfg.baseURL = url
        cfg.save()
        serverConfig = cfg
        api.updateConfig(cfg)
        // Switching servers must not carry server A's session (cookie) or A's saved
        // credentials to server B — clear both and force a fresh login against B.
        if changed {
            api.clearCookies()
            Keychain.delete(Keychain.usernameKey)
            Keychain.delete(Keychain.passwordKey)
            username = nil
            totpRequired = false
            phase = .login
        }
    }

    func makeSessionStore() -> SessionStore { SessionStore(api: api) }
    func makeChatViewModel(session: ChatSession?) -> ChatViewModel {
        ChatViewModel(api: api, stream: stream, session: session)
    }
}
