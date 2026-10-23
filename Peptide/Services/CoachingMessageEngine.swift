import Foundation

/// Picks the single coaching line shown directly under the hero
/// metric trio. Bevel's "Excellent recovery! Target a Strain level
/// of 39%–76% for optimal training today." line was the highest-
/// impact thing on the screen — it turned three numbers into a
/// recommendation. This engine does the same for Atlas's
/// peptide-protocol context.
///
/// Pure function over a snapshot of the user's state, so it's
/// trivial to test: pass `Context`, get `CoachingMessage?`, assert.
/// No HealthKit reads, no DataStore lookups — the caller hands in
/// the values, the engine picks the message.
///
/// Priority cascade (first match wins):
///   1. New install with no protocols → goal-neutral welcome
///   2. No health connection → invite to connect
///   3. Strong recovery + protocols active → push-today nudge
///   4. Weak recovery → take-it-easy nudge
///   5. Short sleep last night → recovery nudge
///   6. After-hours catch-up (adherence low, day winding down) → nudge to log
///   7. On-track default → encouragement tied to next dose
enum CoachingMessageEngine {

    struct CoachingMessage: Equatable, Sendable {
        let icon: String                       // SF Symbol
        let eyebrow: String                    // "COACHING", "WELCOME", etc.
        let title: String                      // the headline line
        let body: String?                      // optional one-line detail
        let tone: Tone
        /// Which branch produced the message. Callers that need to know
        /// (`PrimaryReasonEngine`) compare this, never the display copy,
        /// which changes with wording and language.
        var kind: Kind = .other

        enum Tone: Equatable, Sendable {
            case positive, neutral, cautionary, welcome
        }

        enum Kind: Equatable, Sendable {
            case welcome, connectHealth, onTrack, other,
                 strongRecovery, weakRecovery, shortSleep, catchUp, habitsDue, weeklyReview
        }

        /// What tapping the card does, for messages that ask for something.
        enum Action: Equatable, Sendable {
            case connectHealth, scrollToHabits, scrollToDoses
        }

        var action: Action? {
            switch kind {
            case .connectHealth: return .connectHealth
            case .habitsDue: return .scrollToHabits
            case .catchUp: return .scrollToDoses
            case .welcome, .onTrack, .other, .strongRecovery, .weakRecovery, .shortSleep, .weeklyReview: return nil
            }
        }

        /// True for the get-set-up messages a concrete task should outrank.
        var isOnboarding: Bool { kind == .welcome || kind == .connectHealth }
    }

    struct Context: Equatable, Sendable {
        let hasProtocols: Bool
        let healthConnected: Bool
        let recoveryScore: Int?                 // 0…100, nil = no signal
        let sleepHours: Double?                 // last night's total
        let adherenceRatio: Double              // 0…1, today's progress
        let pendingDoseCount: Int               // unlogged doses today
        let nextDoseAbbreviation: String?       // e.g. "BPC-157"
        let nextDoseTimeDisplay: String?        // e.g. "8:00 PM"
        let hourOfDay: Int                      // 0…23 in user's locale
        /// Days since the user signed up. Drives the welcome-vs-on-
        /// track decision so a long-time user who archives their last
        /// protocol doesn't get "WELCOME — Set up your first protocol"
        /// (audit Biology CRITICAL 3). Pass `nil` for backwards-compat
        /// — the welcome message then defaults to the legacy
        /// !hasProtocols path.
        let memberDays: Int?

        init(
            hasProtocols: Bool,
            healthConnected: Bool,
            recoveryScore: Int? = nil,
            sleepHours: Double? = nil,
            adherenceRatio: Double = 0,
            pendingDoseCount: Int = 0,
            nextDoseAbbreviation: String? = nil,
            nextDoseTimeDisplay: String? = nil,
            hourOfDay: Int = 12,
            memberDays: Int? = nil
        ) {
            self.hasProtocols = hasProtocols
            self.healthConnected = healthConnected
            self.recoveryScore = recoveryScore
            self.sleepHours = sleepHours
            self.adherenceRatio = adherenceRatio
            self.pendingDoseCount = pendingDoseCount
            self.nextDoseAbbreviation = nextDoseAbbreviation
            self.nextDoseTimeDisplay = nextDoseTimeDisplay
            self.hourOfDay = hourOfDay
            self.memberDays = memberDays
        }
    }

    /// Welcome message only fires for genuinely new users — defined
    /// here as `memberDays ≤ 14`. A user who deleted their last
    /// protocol after 3 months would otherwise get a "WELCOME" pill
    /// every time they opened the app, overriding the rest of the
    /// cascade.
    private static let welcomeMemberDayThreshold = 14

    // Tuned thresholds. Kept as static constants so a future tweak
    // doesn't fan out into the algorithm itself.
    private static let strongRecoveryFloor = 75
    private static let weakRecoveryCeiling = 40
    private static let shortSleepCeiling: Double = 6.0
    private static let lateInDayHour = 18    // 6pm cutoff for "catch-up" copy

    static func pick(context: Context) -> CoachingMessage {
        if !context.hasProtocols, isNewMember(context) {
            return welcomeMessage()
        }
        if !context.healthConnected {
            return connectHealthMessage()
        }
        if let recovery = context.recoveryScore, recovery >= strongRecoveryFloor {
            return strongRecoveryMessage(context: context, recovery: recovery)
        }
        if let recovery = context.recoveryScore, recovery <= weakRecoveryCeiling {
            return weakRecoveryMessage(context: context, recovery: recovery)
        }
        if let sleep = context.sleepHours, sleep < shortSleepCeiling, sleep > 0 {
            return shortSleepMessage(sleepHours: sleep)
        }
        if context.hourOfDay >= lateInDayHour, context.pendingDoseCount > 0 {
            return catchUpMessage(pending: context.pendingDoseCount)
        }
        return onTrackMessage(context: context)
    }

    // MARK: - Messages

    /// True when memberDays is unset (back-compat) OR ≤ welcome
    /// threshold. A nil here matches the historical behavior so
    /// existing call sites that don't pass memberDays still work.
    private static func isNewMember(_ context: Context) -> Bool {
        guard let days = context.memberDays else { return true }
        return days <= welcomeMemberDayThreshold
    }

    /// Goal-neutral: protocols are optional, and most new members come
    /// for training, nutrition or recovery.
    private static func welcomeMessage() -> CoachingMessage {
        CoachingMessage(
            icon: "sparkles",
            eyebrow: String(localized: "WELCOME"),
            title: String(localized: "Welcome to Atlas"),
            body: String(localized: "Log a workout, a meal, or a habit — Atlas learns your patterns as you go."),
            tone: .welcome,
            kind: .welcome
        )
    }

    private static func connectHealthMessage() -> CoachingMessage {
        CoachingMessage(
            icon: "heart.text.square.fill",
            eyebrow: String(localized: "GET STARTED"),
            title: String(localized: "Connect Apple Health"),
            body: String(localized: "Unlock Recovery and Sleep scores plus per-protocol HRV correlations."),
            tone: .neutral,
            kind: .connectHealth
        )
    }

    private static func strongRecoveryMessage(context: Context, recovery: Int) -> CoachingMessage {
        let body: String
        if let dose = context.nextDoseAbbreviation, let time = context.nextDoseTimeDisplay {
            body = String(localized: "Recovery is up — good day to nail your \(dose) dose at \(time).")
        } else {
            body = String(localized: "Recovery is up. Good day to push and stay consistent.")
        }
        return CoachingMessage(
            icon: "bolt.heart.fill",
            eyebrow: String(localized: "COACHING"),
            title: String(localized: "Excellent recovery — \(recovery)%"),
            body: body,
            tone: .positive,
            kind: .strongRecovery
        )
    }

    private static func weakRecoveryMessage(context: Context, recovery: Int) -> CoachingMessage {
        CoachingMessage(
            icon: "moon.zzz.fill",
            eyebrow: String(localized: "COACHING"),
            title: String(localized: "Lower recovery — \(recovery)%"),
            body: String(localized: "Consider an easier day. Hydrate, prioritize sleep, and don't skip rest days."),
            tone: .cautionary,
            kind: .weakRecovery
        )
    }

    private static func shortSleepMessage(sleepHours: Double) -> CoachingMessage {
        let display = sleepHours.formatted(.number.precision(.fractionLength(1)))
        return CoachingMessage(
            icon: "bed.double.fill",
            eyebrow: String(localized: "COACHING"),
            title: String(localized: "Short sleep — \(display) h"),
            body: String(localized: "Cap intensity today. A long nap or an earlier wind-down will pay back tomorrow."),
            tone: .cautionary,
            kind: .shortSleep
        )
    }

    static func catchUpMessage(pending: Int) -> CoachingMessage {
        CoachingMessage(
            icon: "clock.badge.exclamationmark.fill",
            eyebrow: String(localized: "COACHING"),
            title: String(localized: "\(pending) doses left today"),
            body: String(localized: "Tap a dose below to log it."),
            tone: .cautionary,
            kind: .catchUp
        )
    }

    private static func onTrackMessage(context: Context) -> CoachingMessage {
        if let dose = context.nextDoseAbbreviation, let time = context.nextDoseTimeDisplay {
            return CoachingMessage(
                icon: "checkmark.circle.fill",
                eyebrow: String(localized: "ON TRACK"),
                title: String(localized: "You're on track"),
                body: String(localized: "Next: \(dose) at \(time). Keep it steady."),
                tone: .positive,
                kind: .onTrack
            )
        }
        return CoachingMessage(
            icon: "checkmark.circle.fill",
            eyebrow: String(localized: "ON TRACK"),
            title: String(localized: "You're on track"),
            body: onTrackBody(context: context),
            tone: .positive,
            kind: .onTrack
        )
    }

    /// Only a protocol user has doses to talk about; anyone else hears about
    /// recovery when there's a score, or the day's logging otherwise.
    private static func onTrackBody(context: Context) -> String {
        if context.hasProtocols {
            return String(localized: "No pending doses right now — enjoy the gap.")
        }
        if context.recoveryScore != nil {
            return String(localized: "Recovery is steady — a normal training day.")
        }
        return String(localized: "Log a workout, a meal, or a habit to keep the day moving.")
    }
}
