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
///   1. New install → welcome
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

        enum Tone: Equatable, Sendable {
            case positive, neutral, cautionary, welcome
        }
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

        init(
            hasProtocols: Bool,
            healthConnected: Bool,
            recoveryScore: Int? = nil,
            sleepHours: Double? = nil,
            adherenceRatio: Double = 0,
            pendingDoseCount: Int = 0,
            nextDoseAbbreviation: String? = nil,
            nextDoseTimeDisplay: String? = nil,
            hourOfDay: Int = 12
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
        }
    }

    // Tuned thresholds. Kept as static constants so a future tweak
    // doesn't fan out into the algorithm itself.
    private static let strongRecoveryFloor = 75
    private static let weakRecoveryCeiling = 40
    private static let shortSleepCeiling: Double = 6.0
    private static let lateInDayHour = 18    // 6pm cutoff for "catch-up" copy

    static func pick(context: Context) -> CoachingMessage {
        if !context.hasProtocols {
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

    private static func welcomeMessage() -> CoachingMessage {
        CoachingMessage(
            icon: "sparkles",
            eyebrow: "WELCOME",
            title: "Set up your first protocol",
            body: "Atlas builds your schedule, tracks every dose, and learns your patterns.",
            tone: .welcome
        )
    }

    private static func connectHealthMessage() -> CoachingMessage {
        CoachingMessage(
            icon: "heart.text.square.fill",
            eyebrow: "GET STARTED",
            title: "Connect Apple Health",
            body: "Unlock Recovery and Sleep scores plus per-protocol HRV correlations.",
            tone: .neutral
        )
    }

    private static func strongRecoveryMessage(context: Context, recovery: Int) -> CoachingMessage {
        let body: String
        if let dose = context.nextDoseAbbreviation, let time = context.nextDoseTimeDisplay {
            body = "Recovery is up — good day to nail your \(dose) dose at \(time)."
        } else {
            body = "Recovery is up. Good day to push and stay consistent."
        }
        return CoachingMessage(
            icon: "bolt.heart.fill",
            eyebrow: "COACHING",
            title: "Excellent recovery — \(recovery)%",
            body: body,
            tone: .positive
        )
    }

    private static func weakRecoveryMessage(context: Context, recovery: Int) -> CoachingMessage {
        CoachingMessage(
            icon: "moon.zzz.fill",
            eyebrow: "COACHING",
            title: "Lower recovery — \(recovery)%",
            body: "Consider an easier day. Hydrate, prioritize sleep, and don't skip rest doses.",
            tone: .cautionary
        )
    }

    private static func shortSleepMessage(sleepHours: Double) -> CoachingMessage {
        let display = String(format: "%.1f", sleepHours)
        return CoachingMessage(
            icon: "bed.double.fill",
            eyebrow: "COACHING",
            title: "Short sleep — \(display) h",
            body: "Cap intensity today. A long nap or an earlier wind-down will pay back tomorrow.",
            tone: .cautionary
        )
    }

    private static func catchUpMessage(pending: Int) -> CoachingMessage {
        let plural = pending == 1 ? "dose" : "doses"
        return CoachingMessage(
            icon: "clock.badge.exclamationmark.fill",
            eyebrow: "COACHING",
            title: "\(pending) \(plural) left today",
            body: "Tap a dose card below — Atlas logs the actual time, not the scheduled one.",
            tone: .cautionary
        )
    }

    private static func onTrackMessage(context: Context) -> CoachingMessage {
        if let dose = context.nextDoseAbbreviation, let time = context.nextDoseTimeDisplay {
            return CoachingMessage(
                icon: "checkmark.circle.fill",
                eyebrow: "ON TRACK",
                title: "You're on track",
                body: "Next: \(dose) at \(time). Keep it steady.",
                tone: .positive
            )
        }
        return CoachingMessage(
            icon: "checkmark.circle.fill",
            eyebrow: "ON TRACK",
            title: "You're on track",
            body: "No pending doses right now — enjoy the gap.",
            tone: .positive
        )
    }
}
