import Foundation

/// Pure rules for the minimum day: whether a day met it, how the week
/// stands, and which gentle line to show. Nothing here ever reads as zero.
enum MinimumDayEngine {

    /// One day's facts, gathered by the caller from the diary and Health.
    struct DayInput: Equatable, Sendable {
        var mealsLogged: Int
        var proteinG: Int
        var proteinTargetG: Int?
        /// Nil when Health isn't connected, so a walk can't be measured.
        var steps: Double?
        var checkedIn: Bool
    }

    /// `unmeasured` parts (no protein target, no Health) neither count
    /// for nor against the day.
    enum PartState: Equatable, Sendable {
        case done, notYet, unmeasured
    }

    static func state(of part: MinimumDay.Part, in input: DayInput) -> PartState {
        switch part {
        case .logFood:
            return input.mealsLogged > 0 ? .done : .notYet
        case .protein:
            guard let target = input.proteinTargetG, target > 0 else { return .unmeasured }
            return input.proteinG >= target ? .done : .notYet
        case .walk:
            guard let steps = input.steps else { return .unmeasured }
            return steps >= Double(MinimumDay.walkSteps) ? .done : .notYet
        case .checkIn:
            return input.checkedIn ? .done : .notYet
        }
    }

    /// Met when every measurable chosen part is done. A day with nothing
    /// measurable chosen isn't met, so an empty choice can't count.
    static func isMet(_ input: DayInput, parts: Set<MinimumDay.Part>) -> Bool {
        let states = parts.map { state(of: $0, in: input) }.filter { $0 != .unmeasured }
        return !states.isEmpty && states.allSatisfy { $0 == .done }
    }

    /// Days met so far in the calendar week holding `date`, up to and
    /// including that day.
    static func metDays(inWeekOf date: Date, metDayKeys: Set<String>, calendar: Calendar) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        let last = calendar.startOfDay(for: date)
        var day = week.start
        var count = 0
        while day <= last {
            if metDayKeys.contains(DayKey.compact(day, calendar: calendar)) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return count
    }

    /// The line under the week count. Never a zero or a reset.
    enum Status: Equatable, Sendable {
        /// Today's minimum is done.
        case doneToday
        /// Nothing met yet, ever.
        case start
        /// The week so far has nothing and last week fell short.
        case newWeek
        /// Yesterday was missed.
        case newDay
        /// On track; today still to do.
        case keepGoing
    }

    struct Summary: Equatable, Sendable {
        let metThisWeek: Int
        let total: Int
        let status: Status

        var weekProgress: Double { min(Double(metThisWeek) / Double(MinimumDay.weeklyGoal), 1) }
    }

    /// `metDayKeys` plus today when today is met but not yet recorded.
    static func summary(
        metDayKeys: Set<String>,
        metToday: Bool,
        now: Date,
        calendar: Calendar
    ) -> Summary {
        var keys = metDayKeys
        if metToday { keys.insert(DayKey.compact(now, calendar: calendar)) }
        let thisWeek = metDays(inWeekOf: now, metDayKeys: keys, calendar: calendar)
        return Summary(
            metThisWeek: thisWeek,
            total: keys.count,
            status: status(keys: keys, metToday: metToday, thisWeek: thisWeek, now: now, calendar: calendar)
        )
    }

    private static func status(
        keys: Set<String>,
        metToday: Bool,
        thisWeek: Int,
        now: Date,
        calendar: Calendar
    ) -> Status {
        if metToday { return .doneToday }
        if keys.isEmpty { return .start }
        if thisWeek == 0,
           let lastWeekDay = calendar.date(byAdding: .day, value: -7, to: now),
           let lastWeekEnd = calendar.dateInterval(of: .weekOfYear, for: lastWeekDay)?.end,
           let lastWeekSunday = calendar.date(byAdding: .day, value: -1, to: lastWeekEnd),
           metDays(inWeekOf: lastWeekSunday, metDayKeys: keys, calendar: calendar) < MinimumDay.weeklyGoal {
            return .newWeek
        }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return .keepGoing }
        return keys.contains(DayKey.compact(yesterday, calendar: calendar)) ? .keepGoing : .newDay
    }
}
