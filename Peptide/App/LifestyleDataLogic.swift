import Foundation

/// Pure-function operations on the lifestyle-data slice of `UserProfile`
/// — nutrition consumption, water, weight history, workout history, and
/// the progress-photo manifest. Extracted from `DataStore` so the logic
/// is unit-testable in isolation; `DataStore` still owns the persisted
/// profile and orchestrates `save()` after each mutation.
///
/// Methods that mutate take `inout UserProfile` so observation on the
/// caller's `@Observable` property fires through the synthesized
/// getter/setter pair — no special bridging needed. Read-only helpers
/// take the profile by value.
///
/// Threading: pure functions on value types — every helper is safe
/// to call from any isolation context. `consumptionKey(for:)`
/// allocates a fresh `ISO8601DateFormatter` per call rather than
/// share a mutable instance.
enum LifestyleDataLogic {

    // MARK: - Weight history

    /// Appends a bodyweight entry, replaces any existing entry with the
    /// same calendar day so the sparkline shows one point per day even
    /// when the user logs more than once, and keeps the array sorted
    /// oldest-first.
    static func logWeight(into profile: inout UserProfile, kg: Double, date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        var trimmed = profile.weightHistory.filter {
            !Calendar.current.isDate($0.date, inSameDayAs: day)
        }
        trimmed.append(WeightEntry(date: date, kg: kg))
        trimmed.sort { $0.date < $1.date }
        profile.weightHistory = trimmed
    }

    /// Weight history with at-most-one entry per calendar day. CloudKit
    /// sync can land a second entry from another device whose timestamp
    /// differs by minutes — `logWeight`'s local dedup doesn't see those
    /// because the merge happens outside this code path. Views that
    /// render the sparkline / weekly delta should read through here so
    /// the "one point per day" invariant survives multi-device use.
    /// Keeps the most recently logged entry within each day.
    static func dedupedWeightHistory(_ profile: UserProfile) -> [WeightEntry] {
        let calendar = Calendar.current
        var byDay: [Date: WeightEntry] = [:]
        for entry in profile.weightHistory {
            let day = calendar.startOfDay(for: entry.date)
            if let existing = byDay[day], existing.date >= entry.date { continue }
            byDay[day] = entry
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// Removes a bodyweight entry by id. Used by the entry-list editor
    /// inside the weight log sheet.
    static func deleteWeight(from profile: inout UserProfile, id: UUID) {
        profile.weightHistory.removeAll { $0.id == id }
    }

    // MARK: - Consumption (meals + water)

    /// Adds a meal's macros to the day's consumption bucket, creating the
    /// bucket on first use. Caller is responsible for the unit choices
    /// (kcal, grams) — `MealScannerService` returns spec-shaped numbers.
    static func logMeal(
        into profile: inout UserProfile,
        calories: Int,
        proteinG: Int,
        carbsG: Int,
        fatG: Int,
        date: Date
    ) {
        let key = consumptionKey(for: date)
        var bucket = profile.dailyConsumption[key] ?? DailyConsumption.empty(on: date)
        bucket.caloriesKcal += calories
        bucket.proteinG += proteinG
        bucket.carbsG += carbsG
        bucket.fatG += fatG
        profile.dailyConsumption[key] = bucket
    }

    /// Reverses a `logMeal` call by subtracting the same macros from the
    /// same day's bucket. Clamps every field at zero so an over-eager
    /// undo can't push the bucket negative. Used by the Undo affordance
    /// on the barcode-scan success screen.
    static func unlogMeal(
        from profile: inout UserProfile,
        calories: Int,
        proteinG: Int,
        carbsG: Int,
        fatG: Int,
        date: Date,
        calendar: Calendar = .current
    ) {
        let amounts = CategoryTotals(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG, entryCount: 1)
        let key = loggedKey(for: date, amounts: amounts, in: profile, calendar: calendar)
        guard var bucket = profile.dailyConsumption[key] else { return }
        bucket.caloriesKcal = max(0, bucket.caloriesKcal - calories)
        bucket.proteinG    = max(0, bucket.proteinG    - proteinG)
        bucket.carbsG      = max(0, bucket.carbsG      - carbsG)
        bucket.fatG        = max(0, bucket.fatG        - fatG)
        profile.dailyConsumption[key] = bucket
    }

    /// The bucket a meal at `date` was most likely added to. Undoing from
    /// the wrong one leaves the meal's macros behind as a phantom total.
    ///
    /// A bucket "covers" the meal when what's left after the other meals
    /// stamped inside its day is at least the meal's macros. The bucket
    /// under today's key wins when it covers: `logMeal` keeps adding to
    /// that key after a time-zone change without re-stamping its date,
    /// so its window can miss meals it holds. Otherwise the covering
    /// bucket stamped nearest the meal wins (ties by key, so the pick
    /// is deterministic); with none, today's key as before.
    /// `mealHistory` must no longer contain the meal being undone.
    private static func loggedKey(
        for date: Date,
        amounts: CategoryTotals,
        in profile: UserProfile,
        calendar: Calendar
    ) -> String {
        let key = consumptionKey(for: date, calendar: calendar)
        func covers(_ bucket: DailyConsumption) -> Bool {
            let end = calendar.date(byAdding: .day, value: 1, to: bucket.date) ?? bucket.date
            var others = CategoryTotals.zero
            for entry in profile.mealHistory where entry.date >= bucket.date && entry.date < end {
                others.add(entry)
            }
            return bucket.caloriesKcal - others.calories >= amounts.calories
                && bucket.proteinG - others.proteinG >= amounts.proteinG
                && bucket.carbsG - others.carbsG >= amounts.carbsG
                && bucket.fatG - others.fatG >= amounts.fatG
        }
        if let bucket = profile.dailyConsumption[key], covers(bucket) { return key }
        func distance(_ bucket: DailyConsumption) -> TimeInterval { abs(bucket.date.timeIntervalSince(date)) }
        // No time zone is more than 26 hours from another, so a bucket
        // stamped two days away can't be where this meal went.
        let nearest = profile.dailyConsumption
            .filter { distance($0.value) < 2 * 86_400 && covers($0.value) }
            .min { lhs, rhs in
                distance(lhs.value) != distance(rhs.value)
                    ? distance(lhs.value) < distance(rhs.value)
                    : lhs.key < rhs.key
            }
        return nearest?.key ?? key
    }

    /// Adds (or, negative, removes) an exact amount of water. `waterOz`
    /// stays the rounded whole-ounce total and `waterOzRemainder` keeps
    /// the fraction, so a metric +1 L reads back as exactly 1000 mL
    /// instead of the 1005 mL that rounding to 34 oz produced. Clamps
    /// the day at zero so an undo can't push it negative.
    static func logWater(into profile: inout UserProfile, fluidOunces: Double, date: Date) {
        let key = consumptionKey(for: date)
        var bucket = profile.dailyConsumption[key] ?? DailyConsumption.empty(on: date)
        bucket.addWater(fluidOunces: fluidOunces)
        profile.dailyConsumption[key] = bucket
    }

    static let millilitresPerFluidOunce = 29.5735

    static func fluidOunces(millilitres: Double) -> Double {
        millilitres / millilitresPerFluidOunce
    }

    static func millilitres(fluidOunces: Double) -> Int {
        Int((fluidOunces * millilitresPerFluidOunce).rounded())
    }

    /// The day's water in the number the user reads: exact millilitres
    /// for metric, whole ounces for imperial.
    static func displayedWater(_ consumption: DailyConsumption, unit: MeasurementUnit) -> Int {
        unit == .metric
            ? millilitres(fluidOunces: consumption.waterFluidOunces)
            : consumption.waterOz
    }

    /// The day's intake as the rings, widgets and Watch show it. Macros
    /// are the sum of the same `mealHistory` entries `mealEntries(in:for:)`
    /// lists, so the total and the list always agree. Water, and any
    /// macros logged before meals were itemised, come from the stored
    /// bucket.
    ///
    /// The bucket is keyed by the day in the time zone the meal was
    /// logged in, so after a time-zone change it no longer lines up with
    /// the day the list shows. Its macros only count for what no entry
    /// explains: an entry explains the bucket when it falls inside the
    /// bucket's own day (as stamped at log time) or inside the asked day.
    ///
    /// Known limits: legacy un-itemised macros can be under-counted when
    /// entries from the asked day overlap the bucket without having been
    /// logged into it (only possible after a time-zone change). Adaptive
    /// TDEE, the weekly check-in and `WeeklySummaryEngine` still read the
    /// raw buckets, so their per-day intake stays keyed by log-time zone.
    static func consumption(
        in profile: UserProfile,
        for date: Date,
        calendar: Calendar = .current
    ) -> DailyConsumption {
        var result = profile.dailyConsumption[consumptionKey(for: date, calendar: calendar)]
            ?? DailyConsumption(date: calendar.startOfDay(for: date),
                                caloriesKcal: 0, proteinG: 0, carbsG: 0, fatG: 0, waterOz: 0)
        // Interval bounds, not `isDate(_:inSameDayAs:)` per entry: this
        // runs on every ring render and history holds up to 3 650 meals.
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let bucketEnd = calendar.date(byAdding: .day, value: 1, to: result.date) ?? result.date
        var listed = CategoryTotals.zero
        var explained = CategoryTotals.zero
        for entry in profile.mealHistory {
            let onDay = entry.date >= dayStart && entry.date < dayEnd
            if onDay { listed.add(entry) }
            if onDay || (entry.date >= result.date && entry.date < bucketEnd) { explained.add(entry) }
        }
        result.caloriesKcal = listed.calories + max(0, result.caloriesKcal - explained.calories)
        result.proteinG = listed.proteinG + max(0, result.proteinG - explained.proteinG)
        result.carbsG = listed.carbsG + max(0, result.carbsG - explained.carbsG)
        result.fatG = listed.fatG + max(0, result.fatG - explained.fatG)
        return result
    }

    // MARK: - Meal entries (per-meal history)

    /// Appends a `MealEntry` AND updates the per-day aggregate. The
    /// rings read the day's macros from history (see `consumption`);
    /// the aggregate still feeds multi-day trends and tells legacy,
    /// un-itemised logs apart. The two stores stay in lockstep via this
    /// method — callers should never write one without the other.
    ///
    /// Trims `mealHistory` to the most recent `maxMealHistoryEntries`
    /// so very heavy users don't bloat the profile blob without
    /// bound. Today's entries are always kept regardless of cap.
    static func logMealEntry(into profile: inout UserProfile, entry: MealEntry) {
        profile.mealHistory.append(entry)
        pruneMealHistoryIfNeeded(into: &profile)
        logMeal(
            into: &profile,
            calories: entry.calories,
            proteinG: entry.proteinG,
            carbsG: entry.carbsG,
            fatG: entry.fatG,
            date: entry.date
        )
    }

    /// Removes a `MealEntry` by id and reverses its contribution to
    /// the aggregate. Idempotent — calling twice does nothing on the
    /// second pass because the entry's already gone. Used by the
    /// Undo affordance on every review screen's success state, and
    /// (eventually) by a meal-history edit/delete UI.
    static func unlogMealEntry(from profile: inout UserProfile, id: UUID, calendar: Calendar = .current) {
        guard let entry = profile.mealHistory.first(where: { $0.id == id }) else { return }
        profile.mealHistory.removeAll { $0.id == id }
        unlogMeal(
            from: &profile,
            calories: entry.calories,
            proteinG: entry.proteinG,
            carbsG: entry.carbsG,
            fatG: entry.fatG,
            date: entry.date,
            calendar: calendar
        )
    }

    /// Replaces a `MealEntry` in place AND moves its contribution
    /// between day aggregates: the old entry's macros are reversed
    /// from its day's bucket and the new values are added to the
    /// (possibly different) day the edit landed on. Editing calories
    /// 500 → 800 or moving an entry across midnight keeps the macro
    /// rings in lockstep with history — the invariant `logMealEntry`
    /// documents, which a bare array replacement silently broke.
    /// No-op when the id isn't in history.
    static func applyMealEntryEdit(into profile: inout UserProfile, updated: MealEntry) {
        guard let index = profile.mealHistory.firstIndex(where: { $0.id == updated.id }) else { return }
        // Out of history while undoing, so `unlogMeal` can tell which
        // bucket held it (see `loggedKey`).
        let previous = profile.mealHistory.remove(at: index)
        unlogMeal(
            from: &profile,
            calories: previous.calories,
            proteinG: previous.proteinG,
            carbsG: previous.carbsG,
            fatG: previous.fatG,
            date: previous.date
        )
        profile.mealHistory.insert(updated, at: index)
        logMeal(
            into: &profile,
            calories: updated.calories,
            proteinG: updated.proteinG,
            carbsG: updated.carbsG,
            fatG: updated.fatG,
            date: updated.date
        )
    }

    /// Per-category macro totals for a single calendar day. Powers
    /// the breakdown card under the macro rings.
    ///
    /// Returns all four categories with zero totals when nothing's
    /// logged in them — the UI renders the empty buckets too so the
    /// card layout stays stable as the user logs through the day.
    /// The `other` bucket captures the gap between `mealHistory`'s
    /// sum and the aggregate, which lets legacy logs (pre-MealEntry,
    /// or logs from flows that haven't been upgraded yet) still
    /// show up in the totals without being mis-attributed.
    static func mealsByCategory(
        in profile: UserProfile,
        for date: Date,
        calendar: Calendar = .current
    ) -> CategoryBreakdown {
        let entries = mealEntries(in: profile, for: date, calendar: calendar)
        var perCategory: [MealCategory: CategoryTotals] = [:]
        for category in MealCategory.allCases {
            perCategory[category] = .zero
        }
        for entry in entries {
            perCategory[entry.category, default: .zero].add(entry)
        }
        let aggregate = consumption(in: profile, for: date, calendar: calendar)
        let mealCalories = entries.reduce(0) { $0 + $1.calories }
        let otherCalories = max(0, aggregate.caloriesKcal - mealCalories)
        let mealProtein = entries.reduce(0) { $0 + $1.proteinG }
        let mealCarbs   = entries.reduce(0) { $0 + $1.carbsG }
        let mealFat     = entries.reduce(0) { $0 + $1.fatG }
        let other = CategoryTotals(
            calories: otherCalories,
            proteinG: max(0, aggregate.proteinG - mealProtein),
            carbsG:   max(0, aggregate.carbsG   - mealCarbs),
            fatG:     max(0, aggregate.fatG     - mealFat),
            entryCount: 0
        )
        return CategoryBreakdown(
            breakfast: perCategory[.breakfast] ?? .zero,
            lunch:     perCategory[.lunch]     ?? .zero,
            dinner:    perCategory[.dinner]    ?? .zero,
            snack:     perCategory[.snack]     ?? .zero,
            other:     other
        )
    }

    /// Returns `mealHistory` filtered to `date`'s calendar day, sorted
    /// newest-first. The day's meal list, and the entries
    /// `consumption(in:for:)` sums, so the two can't disagree.
    static func mealEntries(in profile: UserProfile, for date: Date, calendar: Calendar = .current) -> [MealEntry] {
        profile.mealHistory
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Day browsing, re-logging, portions

    /// Oldest day the Meals day switcher reaches — matches the meal
    /// editor's one-year date floor.
    static let maxMealDayLookback = 365

    /// Start of the day `offset` days from `now`'s day. The Meals tab
    /// keeps an offset rather than a Date so a screen left open past
    /// midnight still means "today". Future offsets clamp to today.
    static func mealDay(offset: Int, from now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let clamped = min(0, max(-maxMealDayLookback, offset))
        return calendar.date(byAdding: .day, value: clamped, to: today) ?? today
    }

    /// When a meal logged while viewing `day` is stamped. Today → `now`.
    /// A past day → that day at now's wall-clock time, so back-filling
    /// lunch at 13:05 lands at 13:05 on that day and auto-categorises
    /// exactly like a live log would.
    static func logTimestamp(on day: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now) { return now }
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        return calendar.date(
            bySettingHour: time.hour ?? 12,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: day
        ) ?? day
    }

    /// A fresh copy of `entry` stamped at `date` — the "Log again"
    /// action. New id so undo, HealthKit mirroring and deletes treat it
    /// as its own meal; category kept because it's the same meal.
    static func relogged(_ entry: MealEntry, at date: Date) -> MealEntry {
        MealEntry(
            date: date,
            category: entry.category,
            name: entry.name,
            calories: entry.calories,
            proteinG: entry.proteinG,
            carbsG: entry.carbsG,
            fatG: entry.fatG,
            sourceID: entry.sourceID,
            source: entry.source,
            components: entry.components
        )
    }

    /// Fresh copies of the meals logged on `sourceDay` — only `category`,
    /// or the whole day when nil — moved onto `targetDay` at the same
    /// wall-clock time, oldest first. Each copy is a new entry, so running
    /// this twice logs the meals twice; callers that must not double a
    /// meal check the target day first, as `DataStore.repeatMeals` does.
    /// An empty source day returns no copies.
    static func copiedMeals(
        from sourceDay: Date,
        to targetDay: Date,
        category: MealCategory? = nil,
        in history: [MealEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MealEntry] {
        let target = calendar.startOfDay(for: targetDay)
        // A copy onto today never lands later than now, so a lunch copied at
        // 08:00 doesn't show up (or reach Apple Health) as a future meal.
        let latestAllowed = calendar.isDate(target, inSameDayAs: now) ? now : .distantFuture
        return history
            .filter { entry in
                calendar.isDate(entry.date, inSameDayAs: sourceDay)
                    && (category == nil || entry.category == category)
            }
            .sorted { $0.date < $1.date }
            .map { relogged($0, at: min(sameClockTime(as: $0.date, on: target, calendar: calendar), latestAllowed)) }
    }

    private static func sameClockTime(as date: Date, on day: Date, calendar: Calendar) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        return calendar.date(
            bySettingHour: time.hour ?? 12,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: day
        ) ?? day
    }

    static let recentMealLimit = 8

    /// The most recent entry for each distinct meal name, newest first.
    /// Names compare trimmed and case-insensitively so "Oatmeal" and
    /// "oatmeal " collapse into one row. Blank names are skipped — there's
    /// nothing to recognise them by.
    static func recentDistinctMeals(in history: [MealEntry], limit: Int = recentMealLimit) -> [MealEntry] {
        var seen: Set<String> = []
        var recent: [MealEntry] = []
        for entry in history.sorted(by: { $0.date > $1.date }) {
            let key = entry.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            recent.append(entry)
            if recent.count >= limit { break }
        }
        return recent
    }

    /// `entry`'s calories and macros multiplied by a portion factor,
    /// rounded to whole units and floored at zero. Always scales the
    /// entry passed in, so ×2 then ×0.5 lands back on the original
    /// instead of compounding rounding.
    static func scaledMacros(of entry: MealEntry, by factor: Double) -> LoggableMeal {
        func scale(_ value: Int) -> Int { max(0, Int((Double(value) * factor).rounded())) }
        return LoggableMeal(
            calories: scale(entry.calories),
            proteinG: scale(entry.proteinG),
            carbsG: scale(entry.carbsG),
            fatG: scale(entry.fatG)
        )
    }

    // MARK: - Meal-logging streak

    /// Consecutive calendar days ending today (or yesterday) where
    /// the user logged at least one meal entry. Mirrors the peptide
    /// dose-logging streak's behaviour: a user who hasn't logged
    /// *yet* today doesn't see the streak break the moment they
    /// open the app — it counts back from yesterday until they log
    /// something for today, at which point it counts back from
    /// today.
    ///
    /// The grace-day treatment makes the streak feel encouraging
    /// rather than punishing — a user opening the app at 8 AM sees
    /// "5 day streak, keep it up" instead of "streak broken, start
    /// over". The streak only breaks if both today and yesterday
    /// are empty.
    static func mealLoggingStreak(in profile: UserProfile, asOf reference: Date = Date()) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: reference)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        // Walk every entry once into a set of days the user logged.
        // O(n) up-front beats O(n × days) on the iteration below.
        var loggedDays: Set<Date> = []
        for entry in profile.mealHistory {
            loggedDays.insert(calendar.startOfDay(for: entry.date))
        }
        guard !loggedDays.isEmpty || !profile.streakFreezeDays.isEmpty else { return 0 }

        // Streak-shielding: a freeze day is treated identically to
        // a logged day for the purpose of consecutive-day counting.
        // Lets a user spend a freeze the morning after a missed
        // day to keep their streak alive.
        let isCovered: (Date) -> Bool = { day in
            loggedDays.contains(day) || StreakFreezeService.isFrozen(day, in: profile)
        }

        // Anchor: start from today if today has a log/freeze, else
        // from yesterday (today is the grace day). If yesterday is
        // also empty, the streak is 0.
        let anchor: Date
        if isCovered(today) {
            anchor = today
        } else if isCovered(yesterday) {
            anchor = yesterday
        } else {
            return 0
        }

        var streak = 0
        var cursor = anchor
        while isCovered(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// All-time best meal-logging streak: the longest run of
    /// consecutive days that were logged or covered by a streak freeze,
    /// matching how `mealLoggingStreak` counts — so a freeze-bridged run
    /// doesn't shrink in "Best" once it ends. Returns the current streak
    /// when nothing higher has happened historically.
    static func bestMealLoggingStreak(in profile: UserProfile, asOf reference: Date = Date()) -> Int {
        let calendar = Calendar.current
        let loggedDays = Set(profile.mealHistory.map { calendar.startOfDay(for: $0.date) })
        guard !loggedDays.isEmpty else { return 0 }
        let isCovered: (Date) -> Bool = { day in
            loggedDays.contains(day) || StreakFreezeService.isFrozen(day, in: profile)
        }

        var best = 0
        var counted: Set<Date> = []
        for day in loggedDays.sorted() where !counted.contains(day) {
            // Back over any freeze days that open the run, then forward
            // to its end.
            var start = day
            while let previous = calendar.date(byAdding: .day, value: -1, to: start), isCovered(previous) {
                start = previous
            }
            var run = 0
            var cursor = start
            while isCovered(cursor) {
                run += 1
                counted.insert(cursor)
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            best = max(best, run)
        }
        // A live streak of freeze days alone never starts a walk above.
        return max(best, mealLoggingStreak(in: profile, asOf: reference))
    }

    /// Soft cap on `mealHistory` so the profile blob can't grow
    /// without bound: 5 meals/day × 365 days × 2 years = 3,650 entries.
    /// A plain entry serialises to ~150 B, but a scanned meal carrying
    /// `components` (per-100 g nutriments for each food) runs ~1 KB, so
    /// a heavy scanner user can reach a few MB here. CloudKit moves an
    /// oversized binary column to an asset rather than failing the
    /// record, but the whole blob is still re-encoded on every save.
    /// Today's entries are always preserved past the cap so the
    /// rings can't lose data mid-day.
    static let maxMealHistoryEntries: Int = 3650

    // MARK: - Outcome check-ins

    /// Logs (or replaces) the daily wellness check-in for the entry's
    /// calendar day. One per day — a second save on the same day
    /// overwrites the first, so the user can edit "no actually my
    /// energy was a 4" without ending up with two entries.
    static func logOutcome(into profile: inout UserProfile, entry: OutcomeEntry) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: entry.date)
        profile.outcomeHistory.removeAll {
            calendar.isDate($0.date, inSameDayAs: dayStart)
        }
        // The check-in keeps its time of day; lookups go through
        // `isDate(_:inSameDayAs:)`, never exact-date equality.
        var stamped = entry
        stamped.updatedAt = Date()
        profile.outcomeHistory.append(stamped)
        // Sort chronological so callers iterating forward see the
        // oldest entry first (matches mealHistory's invariant).
        profile.outcomeHistory.sort { $0.date < $1.date }
    }

    /// Returns the user's check-in for a given calendar day, or nil
    /// when there's nothing logged. Drives the "filled in today?"
    /// state on the prompt card.
    static func outcome(in profile: UserProfile, for date: Date) -> OutcomeEntry? {
        let calendar = Calendar.current
        return profile.outcomeHistory.first {
            calendar.isDate($0.date, inSameDayAs: date)
        }
    }

    /// All check-ins from the last `days` calendar days (inclusive of
    /// today), sorted oldest-first. Powers the trend sparkline and
    /// feeds the correlation engine.
    static func recentOutcomes(in profile: UserProfile, days: Int) -> [OutcomeEntry] {
        let calendar = Calendar.current
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: Date())
        guard let cutoff = calendar.date(byAdding: .day, value: -days + 1, to: today) else { return [] }
        return profile.outcomeHistory.filter { $0.date >= cutoff }
    }

    private static func pruneMealHistoryIfNeeded(into profile: inout UserProfile) {
        guard profile.mealHistory.count > maxMealHistoryEntries else { return }
        let today = Calendar.current.startOfDay(for: Date())
        // Keep every entry from today regardless of cap so the rings
        // are never wrong on the active day, then trim older entries
        // to fit the remaining budget.
        var todays: [MealEntry] = []
        var older: [MealEntry] = []
        todays.reserveCapacity(profile.mealHistory.count)
        older.reserveCapacity(profile.mealHistory.count)
        for entry in profile.mealHistory {
            if Calendar.current.isDate(entry.date, inSameDayAs: today) {
                todays.append(entry)
            } else {
                older.append(entry)
            }
        }
        // Back-filled and re-dated entries break append order, so trim
        // by date or a newer meal could go before an older one.
        older.sort { $0.date < $1.date }
        let trimmedOlder = older.suffix(max(0, maxMealHistoryEntries - todays.count))
        profile.mealHistory = Array(trimmedOlder) + todays
    }

    // MARK: - Workouts

    /// Appends a workout session and keeps the array sorted oldest-first
    /// so the per-day rollup on the Lifestyle card reads stably.
    static func logWorkout(into profile: inout UserProfile, entry: WorkoutEntry) {
        var trimmed = profile.workoutHistory
        trimmed.append(entry)
        trimmed.sort { $0.date < $1.date }
        profile.workoutHistory = trimmed
    }

    static func deleteWorkout(from profile: inout UserProfile, id: UUID) {
        profile.workoutHistory.removeAll { $0.id == id }
    }

    /// Returns (count, totalMinutes) for sessions logged on `date`'s
    /// calendar day. Empty tuple when the user hasn't logged anything
    /// for that day.
    static func workoutSummary(
        of profile: UserProfile,
        for date: Date
    ) -> (count: Int, minutes: Int) {
        let sessions = profile.workoutHistory.filter {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }
        let minutes = sessions.reduce(0) { $0 + $1.durationMinutes }
        return (sessions.count, minutes)
    }

    // MARK: - Progress photos manifest

    /// Records a progress-photo filename. Caller writes the JPEG to
    /// `Documents/<filename>` first; this only updates the manifest.
    /// Idempotent — duplicate filenames are silently ignored.
    static func addProgressPhotoFilename(to profile: inout UserProfile, _ filename: String) {
        guard !profile.progressPhotoFilenames.contains(filename) else { return }
        profile.progressPhotoFilenames.append(filename)
    }

    static func removeProgressPhotoFilename(from profile: inout UserProfile, _ filename: String) {
        profile.progressPhotoFilenames.removeAll { $0 == filename }
    }

    // MARK: - Helpers

    /// Stable, wall-clock-day key for the `dailyConsumption` dictionary.
    /// Must match the user's local day, NOT the UTC day — a meal logged
    /// at 11:00 PM in Auckland would otherwise key under tomorrow's
    /// date and silently disappear from today's rings.
    static func consumptionKey(for date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        // Per-call formatter allocation. The previous shared
        // `nonisolated(unsafe)` instance was only safe while every
        // caller stayed on `@MainActor`; a widget timeline provider
        // or background Task picking this up would have raced on
        // the `timeZone` setter. Construction is a handful of
        // microseconds and dominates none of the calling paths.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: day)
    }

    /// Per-category macro totals returned by `mealsByCategory(in:for:)`.
    /// `other` captures anything in the aggregate that has no matching
    /// `MealEntry` — typically legacy logs or logs from flows that
    /// haven't been upgraded to write `MealEntry`s yet.
    struct CategoryBreakdown: Equatable, Sendable {
        var breakfast: CategoryTotals
        var lunch: CategoryTotals
        var dinner: CategoryTotals
        var snack: CategoryTotals
        var other: CategoryTotals

        /// Sum of all five buckets — sanity-check that this matches
        /// `DailyConsumption` for the same day.
        var totalCalories: Int {
            breakfast.calories + lunch.calories + dinner.calories + snack.calories + other.calories
        }

        /// Ordered list for stable rendering in the breakdown card.
        /// `other` only included when it has content — most users
        /// never see it once every flow writes `MealEntry`.
        var orderedRows: [(MealCategory?, CategoryTotals)] {
            var rows: [(MealCategory?, CategoryTotals)] = [
                (.breakfast, breakfast),
                (.lunch, lunch),
                (.dinner, dinner),
                (.snack, snack),
            ]
            if other.calories > 0 {
                rows.append((nil, other))
            }
            return rows
        }
    }

    struct CategoryTotals: Equatable, Sendable {
        var calories: Int
        var proteinG: Int
        var carbsG: Int
        var fatG: Int
        var entryCount: Int

        static let zero = CategoryTotals(
            calories: 0, proteinG: 0, carbsG: 0, fatG: 0, entryCount: 0
        )

        /// In-place add for the per-category aggregation loop.
        mutating func add(_ entry: MealEntry) {
            calories += entry.calories
            proteinG += entry.proteinG
            carbsG   += entry.carbsG
            fatG     += entry.fatG
            entryCount += 1
        }
    }

}

extension DailyConsumption {
    /// The day's water in exact fluid ounces — the rounded total plus
    /// the remainder metric logs carry.
    var waterFluidOunces: Double {
        Double(waterOz) + (waterOzRemainder ?? 0)
    }

    /// Below this a remainder is floating-point noise from add/undo
    /// round trips, not water.
    private static let waterRemainderEpsilon = 1e-6

    /// Adds (or, negative, removes) an exact amount of water, clamping
    /// the day at zero.
    mutating func addWater(fluidOunces: Double) {
        let exact = max(0, waterFluidOunces + fluidOunces)
        let whole = exact.rounded()
        let remainder = exact - whole
        waterOz = Int(whole)
        waterOzRemainder = abs(remainder) < Self.waterRemainderEpsilon ? nil : remainder
    }
}
