import Foundation

/// Anonymized aggregate the iOS app posts to the AI weekly-summary
/// endpoint. Designed to carry enough signal for the model to write
/// a meaningful 150-word recap, *without* exposing peptide names,
/// raw entry timestamps, UUIDs, or any other identifying data.
///
/// Privacy contract:
///   • No `peptide.name`, `peptide.abbreviation`, or protocol names
///   • No per-entry dates beyond `weekStart`
///   • No body metrics (weight, photos, height)
///   • No raw lab values — only "did the user log any this week"
///   • No free-text fields (notes, journal entries)
///
/// The proxy logs aggregate counts only; nothing crosses the
/// network that could be used to reconstruct the user's protocol.
struct WeeklyAggregate: Codable, Hashable, Sendable {
    /// ISO-8601 date of the Monday that starts the week. Mondays
    /// (not Sundays) so US + Europe agree on the week boundary
    /// — the model needs a stable cadence, not a locale-correct
    /// week-start.
    let weekStart: String

    let compliance: Compliance
    let streak: Streak
    let outcomes: Outcomes?
    let nutrition: Nutrition?
    let biometrics: Biometrics?
    let labs: Labs
    /// Highest-priority observation the on-device InsightEngine
    /// surfaced for the week. Nil when the engine has nothing to
    /// say — the model is instructed not to invent in that case.
    let topInsight: String?

    struct Compliance: Codable, Hashable, Sendable {
        let completed: Int
        let total: Int
        let pct: Double
        /// Best individual day's compliance fraction this week
        /// (0…1). Used by the model to call out "your strongest
        /// day was…" without needing the raw date.
        let bestDayPct: Double
        /// Number of distinct days with at least one logged dose.
        /// Lets the model distinguish "every day, light volume"
        /// from "three days, heavy volume" at the same total.
        let activeDaysCount: Int
    }

    struct Streak: Codable, Hashable, Sendable {
        let current: Int
        let best: Int
    }

    /// 5-dimension outcome check-in averages + change vs. the prior
    /// week. Nil when the user logged fewer than 3 check-ins —
    /// averages over 1-2 days are noise, not signal.
    struct Outcomes: Codable, Hashable, Sendable {
        let energyAvg: Double
        let sleepAvg: Double
        let recoveryAvg: Double
        let moodAvg: Double
        let focusAvg: Double
        /// Composite (mean of all 5) week-over-week delta. Positive
        /// = improving; negative = declining.
        let compositeDelta: Double
        let checkInsCount: Int
    }

    /// Nutrition aggregates. Nil when the user has no calorie
    /// target set OR logged fewer than 2 days of meals — the
    /// summary skips this whole section in that case.
    struct Nutrition: Codable, Hashable, Sendable {
        let avgCalories: Int
        let targetCalories: Int
        let mealLoggingDays: Int
        let proteinAvgG: Int
        let proteinTargetG: Int
    }

    /// HealthKit-derived aggregates. Nil when the user hasn't
    /// connected Apple Health or the period has no HK data.
    struct Biometrics: Codable, Hashable, Sendable {
        let hrvAvg: Int?
        let hrvDelta: Int?
        let rhrAvg: Int?
        let sleepHoursAvg: Double?
    }

    struct Labs: Codable, Hashable, Sendable {
        /// Distinct panels with a new entry this week. Zero when
        /// the user didn't log anything; the model is instructed
        /// not to mention labs in that case.
        let newPanelsLogged: Int
    }
}

/// The completed summary returned by the server. `text` is the
/// AI-generated paragraph; `keyStats` mirror what was sent in the
/// aggregate so the card can render a stats grid without rebuilding
/// the math client-side.
///
/// `kind` distinguishes a real AI response from a deterministic
/// offline fallback the iOS client builds when the server is
/// unreachable — UI surfaces a "Offline summary" chip in that case
/// so the user knows the text didn't go through the AI.
struct WeeklySummary: Codable, Hashable, Sendable, Identifiable {
    /// `weekStart` ISO date doubles as the identifier. One summary
    /// per week.
    var id: String { weekStart }
    let weekStart: String
    let text: String
    let keyStats: KeyStats
    let kind: Kind
    let generatedAt: Date

    enum Kind: String, Codable, Hashable, Sendable {
        /// Sent through the AI proxy and rendered from the model.
        case ai
        /// Server unreachable or user opted out — text was built
        /// on-device from the aggregate using a deterministic
        /// template.
        case offline
    }

    struct KeyStats: Codable, Hashable, Sendable {
        let compliancePct: Double
        let dosesCompleted: Int
        let dosesTotal: Int
        let currentStreak: Int
        let avgCheckInScore: Double?
        let avgCalories: Int?
        let hrvDelta: Int?
    }
}
