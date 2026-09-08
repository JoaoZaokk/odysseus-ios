import Foundation

/// When to ask for an App Store rating.
///
/// Every rating the app had received was unsolicited — three from Germany,
/// all three stars. Nobody who is happy opens the store on their own, so
/// the app has to ask, and only at a moment that has just gone well: right
/// after a reply that streamed cleanly, from someone who has been using it
/// for days, at most once per marketing version. Apple's own cap (three
/// prompts a year) sits on top and is not re-implemented here.
///
/// A plain value, not a view or an observable, so the rule can be tested
/// without SwiftUI: inject the defaults suite, the clock and the version.
struct ReviewGate {
    static let firstLaunchKey = "review.firstLaunch"
    static let repliesKey = "review.successfulReplies"
    static let askedVersionKey = "review.lastAskedVersion"

    static let minReplies = 5
    static let minSessions = 3
    static let minDays = 3.0

    /// Process-lifetime only. A 401 or a failed reply in this launch means no
    /// prompt this launch. Deliberately not persisted: one bad night on a
    /// flaky self-hosted server must not retire the prompt forever.
    @MainActor static var launchIsPoisoned = false

    var defaults: UserDefaults = .standard
    var now: () -> Date = Date.init
    var version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    /// The three-day clock starts at the first launch of a build that carries
    /// the gate. Without a seed, day zero would satisfy "three days".
    static func seedFirstLaunchIfNeeded(_ defaults: UserDefaults = .standard, now: Date = Date()) {
        if defaults.object(forKey: firstLaunchKey) == nil {
            defaults.set(now.timeIntervalSince1970, forKey: firstLaunchKey)
        }
    }

    /// Counts one clean reply and says whether this is the moment to ask.
    /// True at most once per version; the reply counter restarts after an
    /// ask so the next version earns its prompt from scratch.
    @MainActor
    func recordSuccessfulReply(sessionCount: Int) -> Bool {
        let replies = defaults.integer(forKey: Self.repliesKey) + 1
        defaults.set(replies, forKey: Self.repliesKey)
        guard shouldAsk(replies: replies, sessionCount: sessionCount) else { return false }
        defaults.set(version, forKey: Self.askedVersionKey)
        defaults.set(0, forKey: Self.repliesKey)
        return true
    }

    @MainActor
    func shouldAsk(replies: Int, sessionCount: Int) -> Bool {
        if Self.launchIsPoisoned { return false }
        guard replies >= Self.minReplies, sessionCount >= Self.minSessions else { return false }
        guard defaults.string(forKey: Self.askedVersionKey) != version else { return false }
        let first = defaults.double(forKey: Self.firstLaunchKey)
        guard first > 0 else { return false }
        return now().timeIntervalSince1970 - first >= Self.minDays * 86_400
    }
}
