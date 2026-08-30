import Foundation

/// Pure-function transform from a slice of `DataStore` state plus
/// optional HealthKit series → `WeeklyAggregate`. Lives in its own
/// type (rather than as a method on `DataStore`) so the math is
/// unit-testable in isolation and so the HealthKit fetch can stay
/// asynchronous outside the engine.
///
/// Privacy contract: every accessor here strips identifying data
/// before it lands in the aggregate. Peptide names, UUIDs,
/// per-entry timestamps, notes — none of it crosses the engine's
/// boundary into the payload. See `WeeklyAggregate` for the full
/// list of what's excluded.
enum WeeklySummaryEngine {

    /// Minimum days of dose data before the engine returns a
    /// non-nil aggregate. Below this we suppress the summary
    /// entirely — averages over 1-2 days are noise, the AI would
    /// happily invent confidence anyway.
    static let minDoseDaysForSummary: Int = 3

    /// Builds the aggregate for the calendar week containing
    /// `referenceDate`. Returns nil when there isn't enough signal
    /// to write a meaningful summary; the calling service treats
    /// nil as "skip this week, no notification".
    ///
    /// `hrvSeries`, `rhrSeries`, `sleepSeries` are optional —
    /// pass `nil` (or empty arrays) when the user hasn't connected
    /// Apple Health, and the biometrics block is suppressed.
    static func build(
        profile: UserProfile,
        protocols: [PeptideProtocol],
        entries: [ProtocolEntry],
        referenceDate: Date = Date(),
        hrvSeries: [(date: Date, value: Double)] = [],
        rhrSeries: [(date: Date, value: Double)] = [],
        sleepSeries: [(date: Date, value: Double)] = [],
        topInsightCategory: String? = nil
    ) -> WeeklyAggregate? {
        let calendar = Self.isoCalendar
        guard let weekRange = weekRange(containing: referenceDate, calendar: calendar)
        else { return nil }

        let weekEntries = entries.filter { weekRange.contains($0.date) }

        // Active day count gates the whole summary. Fewer than
        // three active days → not enough signal.
        let activeDays = activeDayCount(in: weekEntries, calendar: calendar)
        guard activeDays >= minDoseDaysForSummary else { return nil }

        let compliance = computeCompliance(
            for: weekEntries,
            range: weekRange,
            calendar: calendar
        )

        // Same engine the home ring and the insight line use, so the
        // Sunday recap can't quote a different number than the app did
        // an hour earlier.
        let streakDays = StreakEngine.activeEntriesByDay(
            entries: entries,
            protocols: protocols,
            calendar: calendar
        )
        let streak = WeeklyAggregate.Streak(
            current: StreakEngine.currentStreak(
                entriesByDay: streakDays,
                frozenDayKeys: profile.streakFreezeDays,
                today: referenceDate,
                calendar: calendar
            ),
            best: StreakEngine.bestStreak(
                entriesByDay: streakDays,
                frozenDayKeys: profile.streakFreezeDays,
                today: referenceDate,
                calendar: calendar
            )
        )

        let outcomes = computeOutcomes(
            history: profile.outcomeHistory,
            range: weekRange,
            calendar: calendar
        )

        let nutrition = computeNutrition(
            profile: profile,
            range: weekRange,
            calendar: calendar
        )

        let biometrics = computeBiometrics(
            hrv: hrvSeries,
            rhr: rhrSeries,
            sleep: sleepSeries,
            range: weekRange,
            calendar: calendar
        )

        let labs = WeeklyAggregate.Labs(
            newPanelsLogged: distinctPanelsLogged(
                history: profile.labHistory,
                range: weekRange
            )
        )

        return WeeklyAggregate(
            weekStart: isoDateString(weekRange.lowerBound),
            compliance: compliance,
            streak: streak,
            outcomes: outcomes,
            nutrition: nutrition,
            biometrics: biometrics,
            labs: labs,
            topInsightCategory: topInsightCategory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    // MARK: - Compliance

    private static func computeCompliance(
        for weekEntries: [ProtocolEntry],
        range: Range<Date>,
        calendar: Calendar
    ) -> WeeklyAggregate.Compliance {
        let total = weekEntries.count
        let completed = weekEntries.filter(\.completed).count
        let pct = total > 0 ? Double(completed) / Double(total) : 0

        // Per-day compliance scan for best-day. Iterates the
        // entries once per day, O(days × entries-per-day) which is
        // a handful of operations for a 7-day window.
        var bestDay: Double = 0
        var day = range.lowerBound
        while day < range.upperBound {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let dayEntries = weekEntries.filter { $0.date >= day && $0.date < dayEnd }
            if !dayEntries.isEmpty {
                let dayPct = Double(dayEntries.filter(\.completed).count) / Double(dayEntries.count)
                bestDay = max(bestDay, dayPct)
            }
            day = dayEnd
        }

        return WeeklyAggregate.Compliance(
            completed: completed,
            total: total,
            pct: pct,
            bestDayPct: bestDay,
            activeDaysCount: activeDayCount(in: weekEntries, calendar: calendar)
        )
    }

    private static func activeDayCount(
        in entries: [ProtocolEntry],
        calendar: Calendar
    ) -> Int {
        let days = Set(entries.map { calendar.startOfDay(for: $0.date) })
        return days.count
    }

    // MARK: - Outcomes

    private static func computeOutcomes(
        history: [OutcomeEntry],
        range: Range<Date>,
        calendar: Calendar
    ) -> WeeklyAggregate.Outcomes? {
        let weekEntries = history.filter { range.contains($0.date) }
        guard weekEntries.count >= 3 else { return nil }

        let count = Double(weekEntries.count)
        let energy = weekEntries.reduce(0) { $0 + $1.energy }
        let sleep = weekEntries.reduce(0) { $0 + $1.sleepQuality }
        let recovery = weekEntries.reduce(0) { $0 + $1.recovery }
        let mood = weekEntries.reduce(0) { $0 + $1.mood }
        let focus = weekEntries.reduce(0) { $0 + $1.focus }

        let composite = weekEntries.map(\.composite).reduce(0, +) / count

        // Prior week composite for the delta. Falls back to current
        // week's value when no prior data, yielding a 0 delta.
        let priorRange = priorWeekRange(of: range, calendar: calendar)
        let priorEntries = history.filter { priorRange.contains($0.date) }
        let priorComposite = priorEntries.isEmpty
            ? composite
            : priorEntries.map(\.composite).reduce(0, +) / Double(priorEntries.count)

        return WeeklyAggregate.Outcomes(
            energyAvg: Double(energy) / count,
            sleepAvg: Double(sleep) / count,
            recoveryAvg: Double(recovery) / count,
            moodAvg: Double(mood) / count,
            focusAvg: Double(focus) / count,
            compositeDelta: composite - priorComposite,
            checkInsCount: weekEntries.count
        )
    }

    // MARK: - Nutrition

    private static func computeNutrition(
        profile: UserProfile,
        range: Range<Date>,
        calendar: Calendar
    ) -> WeeklyAggregate.Nutrition? {
        guard let targets = profile.nutritionTargets else { return nil }

        // Iterate every day in the range; each day reads from the
        // per-day consumption bucket if present. Skip days with
        // zero logged calories so the average reflects "logging
        // days", not "all 7 days".
        var totalCal = 0
        var totalProt = 0
        var loggingDays = 0
        var day = range.lowerBound
        while day < range.upperBound {
            // dailyConsumption is keyed by ISO yyyy-MM-dd string
            // (matches LifestyleDataLogic.consumptionKey) so the
            // local-day boundaries line up with where the meal-
            // logging flow wrote the buckets.
            let key = consumptionKey(for: day, calendar: calendar)
            if let bucket = profile.dailyConsumption[key], bucket.caloriesKcal > 0 {
                totalCal += bucket.caloriesKcal
                totalProt += bucket.proteinG
                loggingDays += 1
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        guard loggingDays >= 2 else { return nil }

        return WeeklyAggregate.Nutrition(
            avgCalories: totalCal / loggingDays,
            targetCalories: targets.calories,
            mealLoggingDays: loggingDays,
            proteinAvgG: totalProt / loggingDays,
            proteinTargetG: targets.proteinG
        )
    }

    // MARK: - Biometrics

    private static func computeBiometrics(
        hrv: [(date: Date, value: Double)],
        rhr: [(date: Date, value: Double)],
        sleep: [(date: Date, value: Double)],
        range: Range<Date>,
        calendar: Calendar
    ) -> WeeklyAggregate.Biometrics? {
        let weekHRV = hrv.filter { range.contains($0.date) }
        let weekRHR = rhr.filter { range.contains($0.date) }
        let weekSleep = sleep.filter { range.contains($0.date) }
        if weekHRV.isEmpty && weekRHR.isEmpty && weekSleep.isEmpty { return nil }

        let hrvAvg = average(weekHRV.map(\.value)).map { Int($0.rounded()) }
        let rhrAvg = average(weekRHR.map(\.value)).map { Int($0.rounded()) }
        let sleepAvg = average(weekSleep.map(\.value))

        let priorRange = priorWeekRange(of: range, calendar: calendar)
        let priorHRV = hrv.filter { priorRange.contains($0.date) }
        let priorHRVAvg = average(priorHRV.map(\.value)).map { Int($0.rounded()) }
        let hrvDelta: Int? = {
            guard let a = hrvAvg, let b = priorHRVAvg else { return nil }
            return a - b
        }()

        return WeeklyAggregate.Biometrics(
            hrvAvg: hrvAvg,
            hrvDelta: hrvDelta,
            rhrAvg: rhrAvg,
            sleepHoursAvg: sleepAvg
        )
    }

    // MARK: - Labs

    private static func distinctPanelsLogged(
        history: [LabValue],
        range: Range<Date>
    ) -> Int {
        let weekLabs = history.filter { range.contains($0.date) }
        return Set(weekLabs.map(\.panel)).count
    }

    // MARK: - Date math

    /// ISO-8601 calendar with Monday as the first weekday. Mondays
    /// (not Sundays) so US + Europe agree on the week boundary
    /// — the model needs a stable cadence, not a locale-correct
    /// week-start.
    private static var isoCalendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.firstWeekday = 2 // Monday
        return c
    }

    private static func weekRange(
        containing date: Date,
        calendar: Calendar
    ) -> Range<Date>? {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
        return interval.start..<interval.end
    }

    private static func priorWeekRange(
        of range: Range<Date>,
        calendar: Calendar
    ) -> Range<Date> {
        let start = calendar.date(byAdding: .day, value: -7, to: range.lowerBound) ?? range.lowerBound
        let end = range.lowerBound
        return start..<end
    }

    /// Renders a Date as "yyyy-MM-dd" in the user's local calendar
    /// timezone. Previously the formatter had no `timeZone` set and
    /// defaulted to UTC, so users east of UTC (AEDT, JST) saw the
    /// previous Sunday's date written to the cache key and the AI
    /// payload (audit Biology H8). Caller passes the same calendar
    /// used to compute `weekRange` so the keys stay consistent.
    private static func isoDateString(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }

    /// Mirrors `LifestyleDataLogic.consumptionKey(for:)` (which is
    /// fileprivate, so we can't call it directly). The yyyy-MM-dd
    /// string is anchored to the user's local day — a meal logged
    /// at 11:00 PM in Auckland stays in tonight's bucket, not
    /// tomorrow's. Per-call formatter allocation to avoid sharing a
    /// `nonisolated(unsafe)` instance across actors.
    private static func consumptionKey(for date: Date, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: date)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: day)
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

// `String.nilIfEmpty` lives in DesignSystem/Utilities/StringExtensions.swift;
// reuse it rather than redeclaring locally.
