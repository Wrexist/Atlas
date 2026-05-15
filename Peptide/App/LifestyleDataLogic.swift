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
        date: Date
    ) {
        let key = consumptionKey(for: date)
        guard var bucket = profile.dailyConsumption[key] else { return }
        bucket.caloriesKcal = max(0, bucket.caloriesKcal - calories)
        bucket.proteinG    = max(0, bucket.proteinG    - proteinG)
        bucket.carbsG      = max(0, bucket.carbsG      - carbsG)
        bucket.fatG        = max(0, bucket.fatG        - fatG)
        profile.dailyConsumption[key] = bucket
    }

    /// Adds water (oz) to the day's consumption bucket. Quick-add buttons
    /// on the Lifestyle tab call this with +250 mL ≈ 8.5 oz and +500 mL
    /// ≈ 16.9 oz pre-converted to integer ounces.
    static func logWater(into profile: inout UserProfile, oz: Int, date: Date) {
        let key = consumptionKey(for: date)
        var bucket = profile.dailyConsumption[key] ?? DailyConsumption.empty(on: date)
        bucket.waterOz += oz
        profile.dailyConsumption[key] = bucket
    }

    /// Convenience accessor used by the macro rings — returns the day's
    /// bucket or an empty stub so callers don't have to optional-chain
    /// the dictionary lookup at every render.
    static func consumption(in profile: UserProfile, for date: Date) -> DailyConsumption {
        profile.dailyConsumption[consumptionKey(for: date)]
            ?? DailyConsumption.empty(on: date)
    }

    // MARK: - Meal entries (per-meal history)

    /// Appends a `MealEntry` AND updates the per-day aggregate so the
    /// macro rings keep working without rewriting them to recompute
    /// from history on every render. The two stores stay in lockstep
    /// via this method — callers should never write one without the
    /// other.
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
    static func unlogMealEntry(from profile: inout UserProfile, id: UUID) {
        guard let entry = profile.mealHistory.first(where: { $0.id == id }) else { return }
        profile.mealHistory.removeAll { $0.id == id }
        unlogMeal(
            from: &profile,
            calories: entry.calories,
            proteinG: entry.proteinG,
            carbsG: entry.carbsG,
            fatG: entry.fatG,
            date: entry.date
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
        for date: Date
    ) -> CategoryBreakdown {
        let day = Calendar.current.startOfDay(for: date)
        let entries = profile.mealHistory.filter {
            Calendar.current.isDate($0.date, inSameDayAs: day)
        }
        var perCategory: [MealCategory: CategoryTotals] = [:]
        for category in MealCategory.allCases {
            perCategory[category] = .zero
        }
        for entry in entries {
            perCategory[entry.category, default: .zero].add(entry)
        }
        let aggregate = consumption(in: profile, for: date)
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
    /// newest-first. Used by the (future) meal-history list.
    static func mealEntries(in profile: UserProfile, for date: Date) -> [MealEntry] {
        profile.mealHistory
            .filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date > $1.date }
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
        guard !loggedDays.isEmpty else { return 0 }

        // Anchor: start from today if today has a log, else from
        // yesterday (today is the grace day). If yesterday is also
        // empty, the streak is 0.
        let anchor: Date
        if loggedDays.contains(today) {
            anchor = today
        } else if loggedDays.contains(yesterday) {
            anchor = yesterday
        } else {
            return 0
        }

        var streak = 0
        var cursor = anchor
        while loggedDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// All-time best meal-logging streak. Walks the full history
    /// once, building a sorted list of distinct logged days, then
    /// counts the longest run of consecutive days. O(n log n) for
    /// the sort, fine on the cap of 3,650 entries we enforce.
    /// Returns the current streak when nothing higher has happened
    /// historically.
    static func bestMealLoggingStreak(in profile: UserProfile, asOf reference: Date = Date()) -> Int {
        guard !profile.mealHistory.isEmpty else { return 0 }
        let calendar = Calendar.current
        let days = Set(profile.mealHistory.map { calendar.startOfDay(for: $0.date) }).sorted()
        guard let firstDay = days.first else { return 0 }

        var best = 1
        var currentRun = 1
        var previous = firstDay
        for day in days.dropFirst() {
            if let expected = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(day, inSameDayAs: expected) {
                currentRun += 1
                best = max(best, currentRun)
            } else {
                currentRun = 1
            }
            previous = day
        }
        // Compare against the live streak too — the ongoing run
        // hasn't been counted as "completed" in the loop above.
        return max(best, mealLoggingStreak(in: profile, asOf: reference))
    }

    /// Soft cap on `mealHistory` so the profile blob can't grow
    /// without bound. 5 meals/day × 365 days × 2 years = 3,650
    /// entries × ~150 B serialised ≈ 550 KB. Plenty of headroom for
    /// the typical user without bloating the CloudKit record.
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
        // Normalise the stored date to start-of-day so a re-fetch
        // with a different time-of-day reference still resolves the
        // same entry.
        var normalised = entry
        normalised.updatedAt = Date()
        profile.outcomeHistory.append(normalised)
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
    fileprivate static func consumptionKey(for date: Date) -> String {
        let day = Calendar.current.startOfDay(for: date)
        // Per-call formatter allocation. The previous shared
        // `nonisolated(unsafe)` instance was only safe while every
        // caller stayed on `@MainActor`; a widget timeline provider
        // or background Task picking this up would have raced on
        // the `timeZone` setter. Construction is a handful of
        // microseconds and dominates none of the calling paths.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = Calendar.current.timeZone
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
