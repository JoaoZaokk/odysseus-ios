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

    /// Opt-in biometric app-lock (A2). True → RootView shows the lock screen until
    /// the user authenticates. Set on launch / when returning to foreground.
    @Published var locked: Bool = BiometricLock.appLockEnabled && BiometricLock.available

    /// True once a "keep me signed in" session is active, so we re-persist the
    /// (possibly rotated) cookie when the app backgrounds.
    private(set) var keepSignedIn = false

    private(set) var api: APIClient
    private(set) var stream: ChatStreamClient

    init() {
        let cfg = ServerConfig.load()
        self.serverConfig = cfg
        let client = APIClient(config: cfg)
        self.api = client
        self.stream = ChatStreamClient(api: client)
    }

    /// Called by the lock screen after a successful biometric/passcode check.
    func unlock() { locked = false }

    /// Re-engage the lock when the app goes to the background (if enabled).
    func relockIfNeeded() {
        if BiometricLock.appLockEnabled && BiometricLock.available { locked = true }
    }

    /// Called on launch: check whether the persisted session cookie is still
    /// valid; if so, go straight to the main UI, otherwise show login.
    func bootstrap() async {
        do {
            let status = try await api.status()
            if status.authenticated {
                username = status.username
                keepSignedIn = true        // a restored cookie got us in → keep it fresh
                await loadFeatures()
                phase = .main
            } else {
                await tryAutoLogin()
            }
        } catch {
            // `status()` can THROW (e.g. a 401 with an expired/empty cookie, or a
            // transient network error) — don't jump straight to login, still try a
            // silent re-login from saved credentials. tryAutoLogin lands on the
            // login screen itself if that also fails.
            await tryAutoLogin()
        }
    }

    private func tryAutoLogin() async {
        guard let u = Keychain.get(Keychain.usernameKey),
              let p = Keychain.get(Keychain.passwordKey) else {
            phase = .login; return
        }
        // A1 (opt-in): require Face ID / Touch ID before the saved password is used.
        if BiometricLock.autoLoginGateEnabled && BiometricLock.available {
            guard await BiometricLock.authenticate(reason: "Autenticar para entrar no Odysseus") else {
                phase = .login; return
            }
        }
        do {
            let resp = try await api.login(username: u, password: p, remember: true)
            if resp.totpRequired == true { phase = .login; totpRequired = true; return }
            username = u
            api.persistCookies()           // refresh the persisted session cookie
            keepSignedIn = true
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
                api.persistCookies()       // keep the session across cold launches
                keepSignedIn = true
            } else {
                // "Don't keep me signed in" → wipe any prior persisted session.
                api.clearPersistedCookies()
                keepSignedIn = false
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
        api.clearPersistedCookies()
        Keychain.delete(Keychain.usernameKey)
        Keychain.delete(Keychain.passwordKey)
        keepSignedIn = false
        username = nil
        totpRequired = false
        phase = .login
    }

    /// Re-archive the (possibly rotated) session cookie when the app backgrounds,
    /// so the very latest session survives the next cold launch.
    func persistSessionIfNeeded() {
        if keepSignedIn { api.persistCookies() }
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
            api.clearPersistedCookies()
            Keychain.delete(Keychain.usernameKey)
            Keychain.delete(Keychain.passwordKey)
            keepSignedIn = false
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
