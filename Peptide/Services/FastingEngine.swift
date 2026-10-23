import Foundation

/// Pure computation behind the fasting tracker: elapsed / remaining time,
/// the general-information stage a fast is in, and streaks over the
/// history. Every time value is an absolute interval between two `Date`s,
/// so DST shifts never stretch or shrink a fast; calendar days (for
/// streaks) come from the injected `Calendar`.
enum FastingEngine {

    /// Commonly described phases of a fast, keyed by hours elapsed. The
    /// thresholds are approximate population-level figures surfaced as
    /// general information only — individual timing varies widely.
    enum Stage: Int, CaseIterable, Identifiable, Sendable {
        case fed
        case earlyFasting
        case fatBurning
        case ketosis

        var id: Int { rawValue }

        /// Hours since the fast started at which this stage begins.
        var startHour: Double {
            switch self {
            case .fed:          0
            case .earlyFasting: 4
            case .fatBurning:   12
            case .ketosis:      16
            }
        }

        var title: String {
            switch self {
            case .fed:          String(localized: "Fed", comment: "Fasting stage — still digesting the last meal")
            case .earlyFasting: String(localized: "Early fasting", comment: "Fasting stage")
            case .fatBurning:   String(localized: "Fat burning", comment: "Fasting stage — roughly 12 h onward")
            case .ketosis:      String(localized: "Ketosis", comment: "Fasting stage — roughly 16 h onward")
            }
        }

        var detail: String {
            switch self {
            case .fed:
                String(localized: "Your body is digesting and using energy from your last meal.")
            case .earlyFasting:
                String(localized: "Blood sugar settles and the body starts drawing on stored glycogen.")
            case .fatBurning:
                String(localized: "Around 12 hours in, many people rely more on stored fat for energy.")
            case .ketosis:
                String(localized: "From roughly 16 hours, ketone production commonly begins to rise.")
            }
        }

        var icon: String {
            switch self {
            case .fed:          "fork.knife"
            case .earlyFasting: "hourglass.bottomhalf.filled"
            case .fatBurning:   "flame.fill"
            case .ketosis:      "bolt.fill"
            }
        }

        var next: Stage? { Stage(rawValue: rawValue + 1) }
    }

    /// Range the custom-length stepper allows.
    static let customHoursRange: ClosedRange<Double> = 1...72

    static func clampedTargetHours(_ hours: Double) -> Double {
        guard hours.isFinite else { return FastingProtocol.custom.defaultFastingHours }
        return min(customHoursRange.upperBound, max(customHoursRange.lowerBound, hours))
    }

    // MARK: - One fast

    /// Seconds fasted so far — or in total, once the fast has ended.
    static func elapsed(_ fast: FastSession, at now: Date) -> TimeInterval {
        max(0, (fast.endedAt ?? now).timeIntervalSince(fast.startedAt))
    }

    static func remaining(_ fast: FastSession, at now: Date) -> TimeInterval {
        max(0, fast.targetHours * 3600 - elapsed(fast, at: now))
    }

    /// 0…1 toward the target; 1 once the goal is reached.
    static func progress(_ fast: FastSession, at now: Date) -> Double {
        let target = fast.targetHours * 3600
        guard target > 0 else { return 1 }
        return min(1, elapsed(fast, at: now) / target)
    }

    static func stage(forElapsed elapsed: TimeInterval) -> Stage {
        let hours = elapsed / 3600
        return Stage.allCases.last { hours >= $0.startHour } ?? .fed
    }

    static func stage(of fast: FastSession, at now: Date) -> Stage {
        stage(forElapsed: elapsed(fast, at: now))
    }

    /// Seconds until the next stage begins, or nil in the last stage.
    static func timeUntilNextStage(of fast: FastSession, at now: Date) -> TimeInterval? {
        guard let next = stage(of: fast, at: now).next else { return nil }
        return next.startHour * 3600 - elapsed(fast, at: now)
    }

    /// An ended fast that lasted at least its target.
    static func metGoal(_ fast: FastSession) -> Bool {
        guard let endedAt = fast.endedAt else { return false }
        return endedAt.timeIntervalSince(fast.startedAt) >= fast.targetHours * 3600
    }

    // MARK: - History

    /// Calendar days on which a goal-meeting fast *ended*. A fast from
    /// 20:00 to 12:00 the next day belongs to the day it finished — the
    /// day the user earned it.
    static func completionDays(_ fasts: [FastSession], calendar: Calendar) -> Set<Date> {
        Set(fasts.filter(metGoal).compactMap { fast in
            fast.endedAt.map { calendar.startOfDay(for: $0) }
        })
    }

    /// Consecutive days, ending today, with a completed fast. Today not
    /// yet having one doesn't break the run — the fast may still be in
    /// progress — so counting starts from yesterday in that case.
    static func currentStreak(_ fasts: [FastSession], asOf now: Date, calendar: Calendar) -> Int {
        let days = completionDays(fasts, calendar: calendar)
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            guard let yesterday = previousDay(before: day, calendar: calendar) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let previous = previousDay(before: day, calendar: calendar) else { break }
            day = previous
        }
        return streak
    }

    static func bestStreak(_ fasts: [FastSession], calendar: Calendar) -> Int {
        let days = completionDays(fasts, calendar: calendar).sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for day in days {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: day) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// Mean length of the most recent `limit` ended fasts, or nil if none.
    static func averageDuration(_ fasts: [FastSession], limit: Int = 7) -> TimeInterval? {
        let ended = fasts
            .filter { !$0.isActive }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(limit)
        guard !ended.isEmpty else { return nil }
        let total = ended.reduce(0) { $0 + elapsed($1, at: $1.endedAt ?? $1.startedAt) }
        return total / Double(ended.count)
    }

    /// "16:05" — hours and minutes, for the ring and history rows. Hours
    /// are not wrapped at 24 so a 36-hour fast reads as 36:00.
    static func clock(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(max(0, interval) / 60)
        return String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
    }

    private static func previousDay(before day: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: -1, to: day).map { calendar.startOfDay(for: $0) }
    }
}
