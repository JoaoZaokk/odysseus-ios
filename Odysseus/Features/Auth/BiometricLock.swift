import Foundation
import LocalAuthentication

/// Opt-in biometric security (Face ID / Touch ID, with device-passcode fallback).
/// Both toggles default OFF — the app behaves exactly as before unless the user
/// turns them on in Ajustes → Conta → Segurança.
/// - **App lock (A2):** require auth before showing the app (on launch + return to foreground).
/// - **Auto-login gate (A1):** require auth before the saved password is used for silent re-login.
enum BiometricLock {
    static let appLockKey = "security.appLock"
    static let autoLoginKey = "security.bioForAutoLogin"

    static var appLockEnabled: Bool { UserDefaults.standard.bool(forKey: appLockKey) }
    static var autoLoginGateEnabled: Bool { UserDefaults.standard.bool(forKey: autoLoginKey) }

    /// Whether the device can do biometric/passcode auth at all.
    static var available: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Human label for the available method ("Face ID", "Touch ID", or generic).
    static var label: String {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch c.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "biometria/senha"
        }
    }

    /// Presents the biometric/passcode prompt. Returns true on success.
    /// Uses `.deviceOwnerAuthentication` so a device without biometrics (or a failed
    /// scan) falls back to the device passcode rather than locking the user out.
    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return await withCheckedContinuation { cont in
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }
}
