import Foundation

/// The one implementation of dose-streak math.
///
/// Three copies of this used to exist — `DataStore.currentStreak`,
/// `InsightEngine.calculateStreak` and `WeeklySummaryEngine.doseStreak` —
/// and they disagreed: only the first honoured streak freezes, and the
/// weekly recap tolerated a single missed day where the other two
/// tolerated two. The home ring, the insight line and the Sunday recap
/// could therefore quote three different numbers for the same user.
///
/// The rules, in one place:
///
/// - A day with at least one completed entry extends the streak.
/// - A day with entries but none completed **breaks** it. The user was
///   scheduled and didn't log.
/// - A day with no entries at all is a bye — an every-other-day or
///   weekday protocol has legitimate off days — and doesn't extend the
///   streak either. Up to `emptyDayTolerance` in a row are forgiven;
///   the next one ends the streak.
/// - A day covered by a redeemed streak freeze counts as completed.
/// - Today is allowed to be un-logged without breaking anything: a user
///   opening the app at 09:00 hasn't necessarily dosed yet, so the walk
///   starts at yesterday.
///
/// Callers pass entries already filtered to *active* protocols. A paused
/// protocol's history shouldn't keep crediting a streak the user is no
/// longer running.
enum StreakEngine {

    /// Consecutive bye days forgiven before the streak ends. Two covers
    /// every-other-day and most weekday schedules without letting a
    /// genuinely abandoned protocol coast.
    static let emptyDayTolerance = 2

    /// Hard bound on the backwards walk. A streak longer than a year
    /// isn't worth the loop, and it stops a clock-confused device from
    /// spinning.
    private static let maxLookbackDays = 365

    /// How a single day scores against the streak.
    private enum DayVerdict {
        case extends
        case bye
        case breaks
    }

    // MARK: - Public API

    /// The user's streak as of `today`, walking backwards.
    ///
    /// `entriesByDay` is keyed by `calendar.startOfDay(for:)` and must
    /// already be filtered to active protocols — see
    /// `activeEntriesByDay(entries:protocols:calendar:)`.
    static func currentStreak(
        entriesByDay: [Date: [ProtocolEntry]],
        frozenDayKeys: Set<String>,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let todayStart = calendar.startOfDay(for: today)

        // Grace: an un-logged today doesn't break the streak, it just
        // doesn't extend it yet, so start the walk at yesterday.
        let todayCompleted = entriesByDay[todayStart]?.contains(where: \.completed) ?? false
        let startOffset = todayCompleted ? 0 : 1

        var streak = 0
        var consecutiveEmptyDays = 0

        for dayOffset in startOffset..<maxLookbackDays {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart) else { break }

            switch verdict(for: date, in: entriesByDay, frozenDayKeys: frozenDayKeys, calendar: calendar) {
            case .extends:
                consecutiveEmptyDays = 0
                streak += 1
            case .bye:
                consecutiveEmptyDays += 1
                if consecutiveEmptyDays > emptyDayTolerance { return streak }
            case .breaks:
                return streak
            }
        }

        return streak
    }

    /// The longest streak the history contains, walking forward from the
    /// earliest logged day. Same rules as `currentStreak`, so a
    /// three-times-a-week user's best can exceed a naive
    /// consecutive-calendar-days count.
    static func bestStreak(
        entriesByDay: [Date: [ProtocolEntry]],
        frozenDayKeys: Set<String>,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        guard let earliest = entriesByDay.keys.min() else { return 0 }
        let todayStart = calendar.startOfDay(for: today)

        var best = 0
        var current = 0
        var consecutiveEmptyDays = 0
        var day = earliest

        while day <= todayStart {
            switch verdict(for: day, in: entriesByDay, frozenDayKeys: frozenDayKeys, calendar: calendar) {
            case .extends:
                consecutiveEmptyDays = 0
                current += 1
                best = max(best, current)
            case .bye:
                consecutiveEmptyDays += 1
                if consecutiveEmptyDays > emptyDayTolerance {
                    current = 0
                    consecutiveEmptyDays = 0
                }
            case .breaks:
                current = 0
                consecutiveEmptyDays = 0
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return best
    }

    /// Entries grouped by start-of-day and filtered to active protocols —
    /// the shape both streak functions expect. `DataStore` keeps its own
    /// cached equivalent; other callers hold a flat array and use this.
    static func activeEntriesByDay(
        entries: [ProtocolEntry],
        protocols: [PeptideProtocol],
        calendar: Calendar = .current
    ) -> [Date: [ProtocolEntry]] {
        let activeIDs = Set(protocols.filter { $0.status == .active }.map(\.id))
        let active = entries.filter { activeIDs.contains($0.protocolId) }
        return Dictionary(grouping: active) { calendar.startOfDay(for: $0.date) }
    }

    // MARK: - Private

    private static func verdict(
        for date: Date,
        in entriesByDay: [Date: [ProtocolEntry]],
        frozenDayKeys: Set<String>,
        calendar: Calendar
    ) -> DayVerdict {
        // A redeemed freeze shields the day whether it was empty or
        // logged-and-missed — that's what the user spent it on.
        if !frozenDayKeys.isEmpty, frozenDayKeys.contains(StreakFreezeService.dayKey(for: date)) {
            return .extends
        }

        let dayEntries = entriesByDay[date] ?? []
        if dayEntries.isEmpty { return .bye }
        return dayEntries.contains(where: \.completed) ? .extends : .breaks
    }
}
