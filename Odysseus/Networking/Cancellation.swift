import Foundation

extension Error {
    /// Whether this error means "the work was called off", not "the work failed".
    ///
    /// `URLSession` reports a cancelled request as `URLError.cancelled`, never as
    /// `CancellationError`, so `catch is CancellationError` silently misses it and
    /// a superseded request surfaces as a real failure — a spurious error banner,
    /// and in the voice loop a turn advanced twice.
    ///
    /// One definition for the whole app: this used to be a private copy in both
    /// `SpeechManager` and `VoiceEndpoint`, which is one copy too many for a rule
    /// this easy to get wrong.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        return (self as? URLError)?.code == .cancelled
    }
}
