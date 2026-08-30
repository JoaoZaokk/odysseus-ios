import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Phase { case launching, login, main }

    @Published var phase: Phase = .launching
    @Published var serverConfig: ServerConfig
    @Published var username: String?

    /// False on first launch until the user saves a server address. While false,
    /// RootView shows a mandatory, non-dismissible server-setup gate.
    @Published var serverConfigured = ServerConfig.isConfigured

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
        // The "server" speech engines talk to /api/tts and /api/stt, so they
        // need the authenticated client. Set here rather than per-view: the TTS
        // manager is a singleton shared by every message bubble.
        SpeechManager.shared.api = client
        client.onUnauthenticated = { [weak self] in
            Task { @MainActor in self?.sessionExpired() }
        }
    }

    /// The one reaction to the server rejecting our session, wired in `init`.
    ///
    /// Deliberately does not touch the Keychain: the credentials are still good,
    /// it is the cookie that died, so "keep me signed in" has to survive this.
    /// `loginError` carries the reason, otherwise being thrown back to the login
    /// screen mid-task reads as a crash.
    func sessionExpired() {
        guard phase == .main else { return }   // already at login, or still launching
        api.clearCookies()
        // The archived copy is the same dead cookie. Leaving it there does not
        // keep anyone signed in — `persistCookies()` guards on a non-empty jar,
        // so backgrounding after an expiry would not overwrite it either — it
        // just keeps a known-dead session in the Keychain until the next login.
        api.clearPersistedCookies()
        username = nil
        loginError = APIError.notAuthenticated.errorDescription
        phase = .login
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
        // No server yet → don't hit the placeholder host; the setup gate is showing.
        guard ServerConfig.isConfigured else { phase = .login; return }
        do {
            let status = try await api.status()
            if status.authenticated {
                username = status.username
                keepSignedIn = true        // a restored cookie got us in → keep it fresh
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
            guard await BiometricLock.authenticate(reason: L("Autenticar para entrar no Odysseus")) else {
                phase = .login; return
            }
        }
        do {
            let resp = try await api.login(username: u, password: p, remember: true)
            if resp.totpRequired == true { phase = .login; totpRequired = true; return }
            username = u
            api.persistCookies()           // refresh the persisted session cookie
            keepSignedIn = true
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
                // The credentials go too: a previous login with `remember` on
                // left them in the Keychain, and only `logout()` used to clear
                // them — so unchecking the box silently kept them on device.
                api.clearPersistedCookies()
                Keychain.delete(Keychain.usernameKey)
                Keychain.delete(Keychain.passwordKey)
                keepSignedIn = false
            }
            username = u
            totpRequired = false
            phase = .main
        } catch {
            loginError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func logout() async {
        await api.logout()
        forgetAccount()
    }

    /// Everything that must go when this device stops being signed in to this
    /// account: the live jar, the archived cookie, the credentials, and the
    /// flags that would otherwise auto-login again. Logout and a server switch
    /// are the only two transitions that need all of it, and they used to spell
    /// it out separately.
    private func forgetAccount() {
        api.clearCookies()
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

    func updateServer(_ url: URL) {
        let changed = url != serverConfig.baseURL
        var cfg = serverConfig
        cfg.baseURL = url
        cfg.save()
        serverConfig = cfg
        serverConfigured = true          // dismisses the first-run setup gate
        api.updateConfig(cfg)
        // Switching servers must not carry server A's session (cookie) or A's saved
        // credentials to server B — clear both and force a fresh login against B.
        if changed { forgetAccount() }
    }

    func makeSessionStore() -> SessionStore { SessionStore(api: api) }
    func makeChatViewModel(session: ChatSession?) -> ChatViewModel {
        ChatViewModel(api: api, stream: stream, session: session)
    }
}
