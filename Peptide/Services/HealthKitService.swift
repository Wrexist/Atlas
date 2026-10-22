import Foundation
@preconcurrency import HealthKit

/// Read/write bridge to Apple Health. Every accessor queries HealthKit
/// on demand — the service holds no cached state, so callers get fresh
/// numbers and nothing observes it.
@MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    private init() {}

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Exactly the types the app reads back: HRV and resting heart rate
    /// (Recovery, Biological Age, correlations), VO2 max (Biological Age),
    /// steps (the home health summary and Biological Age) and sleep.
    /// Asking for a type we never query is an App Review liability and
    /// costs the user a permission row they get nothing for. Computed, not
    /// a `static let`, because `HKObjectType` is non-Sendable.
    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.vo2Max),
            HKQuantityType(.stepCount),
            HKCategoryType(.sleepAnalysis),
        ]
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            AppLog.healthKit.error("Authorization request failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    /// True when at least one read type has never been put to the user —
    /// the case for someone who connected Health before VO2 max joined
    /// `readTypes`. HealthKit only shows its sheet for undetermined types,
    /// so this is the honest test for whether asking again does anything.
    func hasUnrequestedReadTypes() async -> Bool {
        guard isAvailable else { return false }
        let types = readTypes
        let status: HKAuthorizationRequestStatus = await withCheckedContinuation { continuation in
            // `@Sendable` keeps the closure nonisolated: HealthKit calls it
            // on its own queue, and an inferred main-actor closure would
            // trap there under Swift 6.
            store.getRequestStatusForAuthorization(toShare: [], read: types) { @Sendable status, error in
                continuation.resume(returning: error == nil ? status : .unknown)
            }
        }
        return status == .shouldRequest
    }

    // MARK: - Nutrition write authorization

    /// HK quantity types we write when the user opts in. Kept as a
    /// computed property (not a static let) because `HKQuantityType`
    /// is non-Sendable and a `static let` of a non-Sendable type on a
    /// MainActor-isolated class produces Swift 6 warnings.
    ///
    /// Fiber is left out: `writeMealEntry` doesn't write a fiber sample
    /// (though `MealEntry.fiberG` now exists), and asking for a write
    /// permission the app never uses would be an empty prompt.
    private var nutritionWriteTypes: Set<HKSampleType> {
        [
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal),
        ]
    }

    /// Asks Apple Health for write permission on the nutrition types.
    /// Separate from `requestAuthorization()` so the user only gets
    /// the meal-write prompt when they explicitly opt in, not on
    /// every fresh install — matches the Lifesum/MFP pattern where
    /// nutrition sync is a deliberate setting toggle.
    ///
    /// HKHealthStore intentionally won't tell us whether the user
    /// granted or denied — Apple's privacy model is "your app should
    /// behave the same either way". We return `true` on success of
    /// the request itself (i.e. the prompt was shown without throwing).
    func requestNutritionWriteAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(
                toShare: nutritionWriteTypes,
                read: []
            )
            return true
        } catch {
            AppLog.healthKit.error(
                "Nutrition write authorization failed: \(error.localizedDescription, privacy: .private)"
            )
            return false
        }
    }

    // MARK: - Nutrition write

    /// Writes a `MealEntry`'s macros to Apple Health as four quantity
    /// samples (energy, protein, carbs, fat). Each sample's
    /// `HKMetadataKeyExternalUUID` is set to the entry's UUID so the
    /// matching `deleteSamples(forEntryID:)` call can find them again
    /// on undo — without that anchor we'd have to delete by date
    /// range, which would clobber concurrent writes from other apps.
    ///
    /// Silent no-op when HealthKit isn't available, the user denied
    /// write permission, or the entry has zero of every macro. Errors
    /// are logged and swallowed — failing to write to HK shouldn't
    /// block the user's in-app log.
    func writeMealEntry(_ entry: MealEntry) async {
        guard isAvailable else { return }

        // `HKMetadataKeyExternalUUID` anchors the samples back to our
        // `MealEntry.id` so delete-on-undo can target exactly what we
        // wrote. `HKMetadataKeyFoodType` carries the food name into
        // Apple Health's nutrition timeline. `HKMetadataKeyMealType`
        // is intentionally omitted — its public values are documented
        // for workouts (pre/intra/post), not generic nutrition logs.
        // The Health app uses sample time-of-day to bucket meals on
        // its own, so the category is implicitly preserved.
        let baseMetadata: [String: Any] = [
            HKMetadataKeyExternalUUID: entry.id.uuidString,
            HKMetadataKeyFoodType: entry.name,
        ]

        // Write every macro as a sample even when the value is zero —
        // a 0g-protein entry IS information ("this meal had no
        // protein"). Skipping zero samples left Apple Health's daily
        // totals incomplete: a day of three meals all with 0g protein
        // would have no protein sample at all, so the day showed
        // blank instead of "0g" (audit Meals L13). Calories still
        // gate on > 0 because writing a 0-kcal sample would be noise
        // in the Health app's calorie chart.
        var samples: [HKQuantitySample] = []
        if entry.calories > 0 {
            samples.append(makeSample(
                type: .dietaryEnergyConsumed,
                unit: .kilocalorie(),
                value: Double(entry.calories),
                date: entry.date,
                metadata: baseMetadata
            ))
        }
        samples.append(makeSample(
            type: .dietaryProtein,
            unit: .gram(),
            value: Double(entry.proteinG),
            date: entry.date,
            metadata: baseMetadata
        ))
        samples.append(makeSample(
            type: .dietaryCarbohydrates,
            unit: .gram(),
            value: Double(entry.carbsG),
            date: entry.date,
            metadata: baseMetadata
        ))
        samples.append(makeSample(
            type: .dietaryFatTotal,
            unit: .gram(),
            value: Double(entry.fatG),
            date: entry.date,
            metadata: baseMetadata
        ))
        // Fiber not written — see `nutritionWriteTypes`.
        guard !samples.isEmpty else { return }

        do {
            try await store.save(samples)
        } catch {
            AppLog.healthKit.error(
                "writeMealEntry failed: \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    /// Removes every nutrition sample previously written for the given
    /// `MealEntry.id`. Used by the Undo affordance on the review-
    /// success screen and (eventually) by an explicit meal-history
    /// delete UI.
    ///
    /// Uses the documented `HKMetadataKeyExternalUUID` predicate so we
    /// only touch samples we wrote, never other apps' data. Routine
    /// for the user to deny delete permission (Apple Health asks
    /// separately) — when that happens we log and drop the request.
    func deleteSamples(forEntryID id: UUID) async {
        guard isAvailable else { return }

        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            operatorType: .equalTo,
            value: id.uuidString
        )
        for type in nutritionWriteTypes {
            do {
                try await store.deleteObjects(of: type, predicate: predicate)
            } catch let hkError as HKError where hkError.code == .errorAuthorizationDenied
                                              || hkError.code == .errorAuthorizationNotDetermined {
                // User hasn't granted delete permission. Logging once
                // is enough — no point hammering on every undo.
                AppLog.healthKit.debug(
                    "deleteSamples denied for \(type.identifier, privacy: .public)"
                )
                return
            } catch {
                AppLog.healthKit.error(
                    "deleteSamples \(type.identifier, privacy: .public) failed: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
    }

    private func makeSample(
        type: HKQuantityTypeIdentifier,
        unit: HKUnit,
        value: Double,
        date: Date,
        metadata: [String: Any]
    ) -> HKQuantitySample {
        HKQuantitySample(
            type: HKQuantityType(type),
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: date,
            end: date,
            metadata: metadata
        )
    }

    // MARK: - Training & body sync

    /// What the "Sync workouts, weight and water" setting writes. Asked
    /// for on its own, like nutrition, so the prompt only appears when
    /// the user turns that setting on.
    private var activityWriteTypes: Set<HKSampleType> {
        [
            HKWorkoutType.workoutType(),
            HKQuantityType(.bodyMass),
            HKQuantityType(.dietaryWater),
        ]
    }

    /// Write access for workouts, weight and water, plus read access to
    /// weight so weigh-ins from a smart scale reach Atlas.
    func requestActivitySyncAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(
                toShare: activityWriteTypes,
                read: [HKQuantityType(.bodyMass)]
            )
            return true
        } catch {
            AppLog.healthKit.error(
                "Activity sync authorization failed: \(error.localizedDescription, privacy: .private)"
            )
            return false
        }
    }

    /// Saves a finished Atlas workout as strength training, tagged with
    /// the session id so deleting it in Atlas removes it from Health.
    func writeWorkout(_ session: WorkoutSession) async {
        guard isAvailable, let end = session.finishedAt else { return }
        do {
            try await Self.saveStrengthWorkout(store: store, id: session.id, start: session.startedAt, end: end)
        } catch {
            AppLog.healthKit.error("writeWorkout failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func deleteWorkout(id: UUID) async {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            operatorType: .equalTo,
            value: id.uuidString
        )
        await deleteOwnObjects(of: HKWorkoutType.workoutType(), predicate: predicate)
    }

    /// `HKWorkoutBuilder` isn't Sendable, so it is created, driven and
    /// dropped inside one nonisolated call.
    nonisolated private static func saveStrengthWorkout(
        store: HKHealthStore,
        id: UUID,
        start: Date,
        end: Date
    ) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)
        try await builder.addMetadata([HKMetadataKeyExternalUUID: id.uuidString])
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }

    /// Mirrors the day's Atlas weigh-in. Atlas keeps one weight per day,
    /// so its earlier sample for that day is replaced, not stacked.
    func writeBodyMass(kg: Double, date: Date) async {
        guard isAvailable else { return }
        await deleteBodyMass(onDayOf: date)
        let sample = makeSample(type: .bodyMass, unit: .gramUnit(with: .kilo), value: kg, date: date, metadata: [:])
        do {
            try await store.save(sample)
        } catch {
            AppLog.healthKit.error("writeBodyMass failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func deleteBodyMass(onDayOf date: Date) async {
        await deleteOwnObjects(of: HKQuantityType(.bodyMass), predicate: ownSamples(onDayOf: date))
    }

    func writeWater(fluidOunces: Double, date: Date) async {
        guard isAvailable, fluidOunces > 0 else { return }
        let sample = makeSample(type: .dietaryWater, unit: .fluidOunceUS(), value: fluidOunces, date: date, metadata: [:])
        do {
            try await store.save(sample)
        } catch {
            AppLog.healthKit.error("writeWater failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// The Undo of a water quick-add: removes Atlas's newest water sample
    /// of that amount on that day.
    func deleteLatestWater(fluidOunces: Double, onDayOf date: Date) async {
        guard isAvailable else { return }
        let unit = HKUnit.fluidOunceUS()
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.dietaryWater), predicate: ownSamples(onDayOf: date))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        do {
            let samples = try await descriptor.result(for: store)
            guard let match = samples.first(where: {
                abs($0.quantity.doubleValue(for: unit) - fluidOunces) < 0.01
            }) else { return }
            try await store.delete(match)
        } catch {
            AppLog.healthKit.error("deleteLatestWater failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Weigh-ins other apps and scales saved in the last `days` days.
    /// Atlas's own samples are skipped so a sync never reads back what
    /// it wrote.
    func externalWeights(days: Int) async -> [WeightEntry] {
        guard isAvailable else { return [] }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(
                type: HKQuantityType(.bodyMass),
                predicate: HKQuery.predicateForSamples(withStart: start, end: end)
            )],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        do {
            let ownBundleID = Bundle.main.bundleIdentifier
            return try await descriptor.result(for: store)
                .filter { $0.sourceRevision.source.bundleIdentifier != ownBundleID }
                .map {
                    // The sample's own id, so a deleted import stays dismissed.
                    WeightEntry(id: $0.uuid, date: $0.startDate, kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
                }
        } catch {
            AppLog.healthKit.error("externalWeights failed: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    private func ownSamples(onDayOf date: Date) -> NSPredicate {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? date
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
    }

    private func deleteOwnObjects(of type: HKObjectType, predicate: NSPredicate) async {
        guard isAvailable else { return }
        do {
            _ = try await store.deleteObjects(of: type, predicate: predicate)
        } catch {
            AppLog.healthKit.debug(
                "deleteObjects \(type.identifier, privacy: .public) failed: \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    // MARK: - Heart Rate

    func averageRestingHeartRate(days: Int) async -> Double? {
        await averageQuantity(type: .restingHeartRate, unit: .count().unitDivided(by: .minute()), days: days)
    }

    // MARK: - HRV

    func averageHRV(days: Int) async -> Double? {
        await averageQuantity(type: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), days: days)
    }

    /// Returns one HRV value per day (in ms) over the past `days`. Empty
    /// days are dropped — the chart layer interpolates visually. Used by
    /// the Analytics → HealthKit correlation overlay (slot 3 in
    /// `docs/APP_STORE_SCREENSHOTS_GUIDE_1.md`).
    func dailyHRV(days: Int) async -> [(date: Date, value: Double)] {
        await dailyQuantity(
            type: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            days: days,
            options: .discreteAverage,
            extract: { $0.averageQuantity() }
        )
    }

    /// One resting-heart-rate value per day (bpm). Powers the
    /// biometric correlation engine's "dose days vs off days"
    /// comparison alongside HRV and sleep.
    func dailyRestingHeartRate(days: Int) async -> [(date: Date, value: Double)] {
        await dailyQuantity(
            type: .restingHeartRate,
            unit: .count().unitDivided(by: .minute()),
            days: days,
            options: .discreteAverage,
            extract: { $0.averageQuantity() }
        )
    }

    /// Sleep hours per night, attributed to the wake-up day. Apple
    /// Watch (and most third-party trackers) write sleep samples
    /// across midnight; convention here is "the night that ended
    /// on date X" gets attributed to X. Lets a Tuesday dose →
    /// Wednesday-morning HRV correlation read naturally.
    ///
    /// Merges overlapping samples so the Apple Watch + Pillow /
    /// AutoSleep duplicating their own samples doesn't double a
    /// night's total.
    func dailySleepHours(days: Int) async -> [(date: Date, value: Double)] {
        guard isAvailable, days > 0 else { return [] }
        let calendar = Calendar.current
        // Use calendar day arithmetic, not a hardcoded 86_400s: on a DST
        // transition day (23h or 25h) startOfToday + 86_400 lands an hour
        // off the next midnight and skews the window.
        let startOfToday = calendar.startOfDay(for: Date())
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startOfToday),
              let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )

        do {
            let samples = try await descriptor.result(for: store)
            let asleep = samples.filter(Self.isAsleep)
            // Merge overlapping intervals before bucketing so a
            // night with two trackers doesn't double-count.
            let intervals = asleep
                .map { (start: $0.startDate, end: $0.endDate) }
                .sorted { $0.start < $1.start }
            var merged: [(start: Date, end: Date)] = []
            for interval in intervals {
                if var last = merged.last, last.end >= interval.start {
                    last.end = max(last.end, interval.end)
                    merged[merged.count - 1] = last
                } else {
                    merged.append(interval)
                }
            }
            // Bucket by the wake-up day (the day the interval
            // ended). Sleeping past midnight attributes to the
            // morning's date — what the user thinks of as
            // "Wednesday's sleep".
            var buckets: [Date: TimeInterval] = [:]
            for interval in merged {
                let wakeDay = calendar.startOfDay(for: interval.end)
                buckets[wakeDay, default: 0] += interval.end.timeIntervalSince(interval.start)
            }
            return buckets
                .sorted { $0.key < $1.key }
                .map { ($0.key, $0.value / 3600.0) }
        } catch {
            AppLog.healthKit.error(
                "dailySleepHours query failed: \(error.localizedDescription, privacy: .private)"
            )
            return []
        }
    }

    // MARK: - Cardio fitness

    /// One VO2 max value per day that has one (ml/kg/min). Apple Watch
    /// writes these only after outdoor walks, runs and hikes, so expect
    /// gaps of days or weeks.
    func dailyVO2Max(days: Int) async -> [(date: Date, value: Double)] {
        await dailyQuantity(
            type: .vo2Max,
            unit: HKUnit.literUnit(with: .milli)
                .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute())),
            days: days,
            options: .discreteAverage,
            extract: { $0.averageQuantity() }
        )
    }

    // MARK: - Activity

    /// Total steps per day that has any, over the past `days`.
    func dailySteps(days: Int) async -> [(date: Date, value: Double)] {
        await dailyQuantity(
            type: .stepCount,
            unit: .count(),
            days: days,
            options: .cumulativeSum,
            extract: { $0.sumQuantity() }
        )
    }

    func averageSteps(days: Int) async -> Double? {
        guard isAvailable, days > 0 else { return nil }

        // Average over days that actually have step data, not the full
        // window — a user who synced steps on 3 of 7 days shouldn't see
        // their daily average halved by dividing the total by 7.
        // `dailyQuantity` buckets per day and skips empty days.
        let daily = await dailySteps(days: days)
        guard !daily.isEmpty else { return nil }
        let total = daily.reduce(0.0) { $0 + $1.value }
        return total / Double(daily.count)
    }

    // MARK: - Sleep

    /// True for any "asleep" sleep-analysis sample. Includes
    /// `.asleepUnspecified` (raw value 1, shared with the deprecated
    /// `.asleep`), which most third-party sleep apps and pre-iOS-16
    /// data write instead of the staged values — excluding it zeroed
    /// sleep for those users and poisoned Recovery/Bio-Age downstream.
    /// Excludes `.inBed` and `.awake`.
    private static func isAsleep(_ sample: HKCategorySample) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
            return true
        default:
            return false
        }
    }

    /// Mean of `dailySleepHours`, so every surface shares one
    /// definition of a night: calendar-aligned, keyed by the wake-up
    /// day, with a nap counted into its day instead of as an extra
    /// night. Averages only the nights that have data, not the window.
    func averageSleepHours(days: Int) async -> Double? {
        let nights = await dailySleepHours(days: days)
        guard !nights.isEmpty else { return nil }
        return nights.reduce(0.0) { $0 + $1.value } / Double(nights.count)
    }

    /// The most recent night's total. Looks back two wake-up days so
    /// between midnight and waking (today's bucket still empty) it
    /// returns last night instead of nothing.
    func lastNightSleepHours() async -> Double? {
        await dailySleepHours(days: 2).last?.value
    }

    /// Every staged sleep segment from the last 30 hours, for
    /// `SleepScoreEngine.night(from:)` to pick last night out of. The
    /// window is wide on purpose: at 1 a.m. last night's sleep ended
    /// about 18 hours ago. `.inBed` is dropped because it overlaps the
    /// asleep stages and would double the night.
    func recentSleepSegments() async -> [SleepScoreEngine.Segment] {
        guard isAvailable else { return [] }
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-30 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )

        do {
            let samples = try await descriptor.result(for: store)
            return samples.compactMap { sample in
                guard let stage = Self.sleepStage(sample) else { return nil }
                return SleepScoreEngine.Segment(
                    stage: stage,
                    start: sample.startDate,
                    end: sample.endDate,
                    source: sample.sourceRevision.source.bundleIdentifier
                )
            }
        } catch {
            AppLog.healthKit.error("recentSleepSegments query failed: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    private static func sleepStage(_ sample: HKCategorySample) -> SleepScoreEngine.Stage? {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleepDeep: return .deep
        case .asleepCore: return .core
        case .asleepREM: return .rem
        case .asleepUnspecified: return .unspecified
        case .awake: return .awake
        default: return nil
        }
    }

    // MARK: - Private Helpers

    private func averageQuantity(type: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> Double? {
        guard isAvailable else { return nil }

        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(type), predicate: predicate),
            options: .discreteAverage
        )

        do {
            let result = try await descriptor.result(for: store)
            return result?.averageQuantity()?.doubleValue(for: unit)
        } catch {
            AppLog.healthKit.error("averageQuantity \(type.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    /// Bucketed daily values for a quantity type. `extract` chooses which
    /// statistic to read out of each daily bucket (e.g. `averageQuantity`
    /// for HRV, `sumQuantity` for steps). Days with no samples are
    /// skipped — never zero-filled, since zero is meaningfully different
    /// from "no data" for biometrics.
    private func dailyQuantity(
        type: HKQuantityTypeIdentifier,
        unit: HKUnit,
        days: Int,
        options: HKStatisticsOptions,
        extract: @escaping (HKStatistics) -> HKQuantity?
    ) async -> [(date: Date, value: Double)] {
        guard isAvailable, days > 0 else { return [] }

        let calendar = Calendar.current
        // Use calendar day arithmetic, not a hardcoded 86_400s: on a DST
        // transition day (23h or 25h) startOfToday + 86_400 lands an hour
        // off the next midnight and skews the window.
        let startOfToday = calendar.startOfDay(for: Date())
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startOfToday),
              let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(type), predicate: predicate),
            options: options,
            anchorDate: startDate,
            intervalComponents: DateComponents(day: 1)
        )

        do {
            let collection = try await descriptor.result(for: store)
            var buckets: [(date: Date, value: Double)] = []
            collection.enumerateStatistics(from: startDate, to: endDate) { stats, _ in
                if let quantity = extract(stats) {
                    buckets.append((stats.startDate, quantity.doubleValue(for: unit)))
                }
            }
            return buckets
        } catch {
            AppLog.healthKit.error("dailyQuantity \(type.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }
}
