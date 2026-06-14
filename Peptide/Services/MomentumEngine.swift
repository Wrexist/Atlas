import Foundation

/// One day's snapshot of the user's Atlas Score, kept on
/// `UserProfile.momentumHistory` so the progress surface can chart the
/// trend. `score` is the cumulative lifetime total at end of that day;
/// `earned` is how much was banked that day. Capped to a rolling window
/// on write so the profile blob stays small.
struct MomentumDayPoint: Codable, Hashable, Sendable, Identifiable {
    /// Start-of-day in the user's calendar.
    let date: Date
    let score: Int
    let earned: Int

    var id: Date { date }
}

/// Pure computation for the unified "Atlas Score" — one earned number
/// that grows only from real, logged behavior (habits, dose adherence,
/// nutrition). Value-in / value-out so it's trivially unit-testable and
/// carries no side effects; persistence + accrual live on `DataStore`.
///
/// Design rules (kept honest on purpose):
///   • Points are only awarded for things the user actually did today.
///   • Each domain is capped, and the daily ceiling is split across the
///     domains that *apply* today — a habits-only user who completes
///     every habit still earns a full day, exactly like a user juggling
///     habits + doses + nutrition. This mirrors `RecoveryScoreEngine`'s
///     redistributed-weight handling so partial data is never penalised.
///   • Levels come fast early (quick first wins) and slow down later so
///     a high level reads as genuinely earned.
enum MomentumEngine {

    // MARK: - Tuning

    /// Most points a single perfect day can bank. Tuned so a fresh user
    /// reaches the first couple of levels within their first perfect days.
    static let dailyMaxPoints = 60

    /// Level curve. `pointsRequired(forLevel:)` is a soft-cap power curve:
    /// level 1 costs nothing, and each subsequent level costs a little
    /// more than the last.
    private static let levelBase = 50.0
    private static let levelExponent = 1.35
    private static let maxLevel = 999

    // MARK: - Inputs

    /// Today's raw signals, all cheaply sourced from in-memory state so
    /// accrual never touches disk on the save hot-path. Optional domains
    /// (workouts, recovery) are intentionally omitted for now — they're
    /// additive, so leaving them out never lowers anyone's score.
    struct Inputs: Equatable, Sendable {
        /// Habits the schedule marked due today, and how many of those are done.
        var habitsDone: Int
        var habitsDue: Int
        /// Scheduled doses for today, and how many are completed.
        var doseEntriesToday: Int
        var doseCompletedToday: Int
        /// Whether the user committed to macro targets (makes nutrition a
        /// tracked domain even on a day they haven't logged yet).
        var hasNutritionTargets: Bool
        /// Whether at least one meal was logged today.
        var mealLoggedToday: Bool

        init(
            habitsDone: Int = 0,
            habitsDue: Int = 0,
            doseEntriesToday: Int = 0,
            doseCompletedToday: Int = 0,
            hasNutritionTargets: Bool = false,
            mealLoggedToday: Bool = false
        ) {
            self.habitsDone = habitsDone
            self.habitsDue = habitsDue
            self.doseEntriesToday = doseEntriesToday
            self.doseCompletedToday = doseCompletedToday
            self.hasNutritionTargets = hasNutritionTargets
            self.mealLoggedToday = mealLoggedToday
        }
    }

    /// Points earned for today's behavior, 0…`dailyMaxPoints`. Each active
    /// domain contributes its 0…1 completion fraction times an equal share
    /// of the daily ceiling, so the ceiling is the same whether one domain
    /// or three are active today.
    static func dailyPoints(_ inputs: Inputs) -> Int {
        var domainFractions: [Double] = []

        if inputs.habitsDue > 0 {
            domainFractions.append(clamp01(Double(inputs.habitsDone) / Double(inputs.habitsDue)))
        }
        if inputs.doseEntriesToday > 0 {
            domainFractions.append(clamp01(Double(inputs.doseCompletedToday) / Double(inputs.doseEntriesToday)))
        }
        // Nutrition counts as an active domain when the user opted into
        // targets, or — for users without targets — only on days they
        // actually logged, so it never drags down a habits-only day.
        if inputs.hasNutritionTargets {
            domainFractions.append(inputs.mealLoggedToday ? 1.0 : 0.0)
        } else if inputs.mealLoggedToday {
            domainFractions.append(1.0)
        }

        guard !domainFractions.isEmpty else { return 0 }
        let perDomainMax = Double(dailyMaxPoints) / Double(domainFractions.count)
        let total = domainFractions.reduce(0.0) { $0 + $1 * perDomainMax }
        return Int(total.rounded())
    }

    // MARK: - Levels

    /// Cumulative points required to *reach* `level`. Level 1 is the
    /// baseline and costs nothing.
    static func pointsRequired(forLevel level: Int) -> Int {
        guard level > 1 else { return 0 }
        return Int((levelBase * pow(Double(level - 1), levelExponent)).rounded())
    }

    /// The level a given cumulative score sits at (always ≥ 1).
    static func level(for score: Int) -> Int {
        guard score > 0 else { return 1 }
        var level = 1
        while level < maxLevel && pointsRequired(forLevel: level + 1) <= score {
            level += 1
        }
        return level
    }

    // MARK: - Tiers

    /// Cosmetic prestige band layered over the level number. Earned, not
    /// purchased — it's purely a function of how far the user has come.
    enum Tier: String, Sendable, CaseIterable {
        case bronze, silver, gold, platinum, diamond

        static func forLevel(_ level: Int) -> Tier {
            switch level {
            case ..<10:   return .bronze
            case 10..<20: return .silver
            case 20..<40: return .gold
            case 40..<70: return .platinum
            default:      return .diamond
            }
        }

        var name: String {
            switch self {
            case .bronze:   return "Bronze"
            case .silver:   return "Silver"
            case .gold:     return "Gold"
            case .platinum: return "Platinum"
            case .diamond:  return "Diamond"
            }
        }

        var symbol: String {
            switch self {
            case .bronze:   return "shield.fill"
            case .silver:   return "shield.lefthalf.filled"
            case .gold:     return "rosette"
            case .platinum: return "crown.fill"
            case .diamond:  return "diamond.fill"
            }
        }

        /// 24-bit RGB used by the UI edge (`Color(hex:)`). Distinct, warm-to-cool
        /// progression so the band reads at a glance.
        var tintHex: UInt32 {
            switch self {
            case .bronze:   return 0xCD7F4F
            case .silver:   return 0xB8C0C8
            case .gold:     return 0xD4A844
            case .platinum: return 0x8FD0C4
            case .diamond:  return 0x7CC5FF
            }
        }
    }

    // MARK: - Snapshot

    /// Everything the UI needs to render the Atlas Score, derived from the
    /// stored cumulative score plus today's banked points.
    struct Snapshot: Equatable, Sendable {
        let score: Int
        let level: Int
        let tier: Tier
        /// 0…1 toward the next level.
        let progressInLevel: Double
        let pointsIntoLevel: Int
        /// Points spanning the current level (floor → ceiling).
        let pointsForNextLevel: Int
        /// Points banked today (drives the "+N today" affordance).
        let todayEarned: Int

        var pointsToNextLevel: Int { max(0, pointsForNextLevel - pointsIntoLevel) }
    }

    static func snapshot(score: Int, todayEarned: Int) -> Snapshot {
        let level = level(for: score)
        let floorPoints = pointsRequired(forLevel: level)
        let ceilingPoints = pointsRequired(forLevel: level + 1)
        let span = max(1, ceilingPoints - floorPoints)
        let into = max(0, score - floorPoints)
        return Snapshot(
            score: score,
            level: level,
            tier: .forLevel(level),
            progressInLevel: clamp01(Double(into) / Double(span)),
            pointsIntoLevel: into,
            pointsForNextLevel: span,
            todayEarned: max(0, todayEarned)
        )
    }

    // MARK: - Helpers

    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}
