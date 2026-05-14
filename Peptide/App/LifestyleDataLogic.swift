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
/// Threading: callsites in `DataStore` are all `@MainActor`-isolated,
/// so the static `consumptionKeyFormatter` mutation is serialized
/// without extra locking. If a future caller fires from a non-MainActor
/// context, lift the formatter into a per-call allocation or add
/// `@MainActor` here.
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
        consumptionKeyFormatter.timeZone = Calendar.current.timeZone
        return consumptionKeyFormatter.string(from: day)
    }

    /// `static let` so we don't pay the ~0.5 ms allocation on every
    /// `consumption(for:)` call — the macro rings call this on every
    /// render. `nonisolated(unsafe)` because `ISO8601DateFormatter` is
    /// not `Sendable`; the safety invariant ("only ever mutated from
    /// DataStore's `@MainActor` callsites") is documented at the top
    /// of this file. Move to per-call allocation or `@MainActor` if a
    /// future caller fires from a non-MainActor context.
    private nonisolated(unsafe) static let consumptionKeyFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
