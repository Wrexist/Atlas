import Foundation
@preconcurrency import HealthKit
import WidgetKit

struct HealthSnapshot {
    let heartRate: Double?         // bpm, 7-day avg
    let restingHeartRate: Double?  // bpm, 7-day avg
    let hrv: Double?               // ms, 7-day avg
    let weight: Double?            // kg, latest
    let steps: Double?             // daily avg steps, 7 days
    let sleep: Double?             // daily avg hours, 7 days
    let capturedAt: Date
}

@MainActor @Observable
final class HealthKitService {
    static let shared = HealthKitService()

    @ObservationIgnored private let store = HKHealthStore()
    private(set) var cachedSnapshot: HealthSnapshot?
    private var isBackgroundDeliveryStarted = false
    /// Active observer queries. Tracked so stopBackgroundDelivery can stop them
    /// — disableAllBackgroundDelivery alone leaves the observer queries running.
    @ObservationIgnored private var activeObserverQueries: [HKObserverQuery] = []

    private init() {}

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }

        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.bodyMass),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKCategoryType(.sleepAnalysis),
        ]

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            AppLog.healthKit.error("Authorization request failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    // MARK: - Background Delivery

    func startBackgroundDelivery() async {
        guard isAvailable, !isBackgroundDeliveryStarted else { return }
        isBackgroundDeliveryStarted = true

        let quantityTypes: [(HKQuantityTypeIdentifier, HKUpdateFrequency)] = [
            (.heartRate, .immediate),
            (.heartRateVariabilitySDNN, .immediate),
            (.restingHeartRate, .hourly),
            (.bodyMass, .daily),
            (.stepCount, .daily),
            (.activeEnergyBurned, .daily),
        ]

        for (typeId, frequency) in quantityTypes {
            await enableAndObserve(HKQuantityType(typeId), frequency: frequency)
        }
        await enableAndObserve(HKCategoryType(.sleepAnalysis), frequency: .daily)

        // Populate cache immediately so Analytics has data on first open
        await refreshSnapshot()
    }

    func stopBackgroundDelivery() {
        for query in activeObserverQueries {
            store.stop(query)
        }
        activeObserverQueries.removeAll()
        store.disableAllBackgroundDelivery { _, _ in }
        isBackgroundDeliveryStarted = false
    }

    func refreshSnapshot() async {
        guard isAvailable else { return }

        let hr = await averageHeartRate(days: 7)
        let rhr = await averageRestingHeartRate(days: 7)
        let hrv = await averageHRV(days: 7)
        let weight = await latestWeight()
        let steps = await averageSteps(days: 7)
        let sleep = await averageSleepHours(days: 7)

        cachedSnapshot = HealthSnapshot(
            heartRate: hr,
            restingHeartRate: rhr,
            hrv: hrv,
            weight: weight,
            steps: steps,
            sleep: sleep,
            capturedAt: Date()
        )

        WidgetCenter.shared.reloadAllTimelines()
    }

    private func enableAndObserve(_ sampleType: HKSampleType, frequency: HKUpdateFrequency) async {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                store.enableBackgroundDelivery(for: sampleType, frequency: frequency) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            // Routine on simulator and when the user denied authorization.
            AppLog.healthKit.debug("enableBackgroundDelivery skipped for \(sampleType.identifier, privacy: .public): \(error.localizedDescription, privacy: .private)")
            return
        }

        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
            // Call immediately — our refresh runs in a separate Task per Apple's guidance
            completionHandler()
            if let error {
                AppLog.healthKit.error("Observer query error: \(error.localizedDescription, privacy: .private)")
                return
            }
            Task { @MainActor in
                await self?.refreshSnapshot()
            }
        }
        store.execute(query)
        activeObserverQueries.append(query)
    }

    // MARK: - Heart Rate

    func averageHeartRate(days: Int) async -> Double? {
        await averageQuantity(type: .heartRate, unit: .count().unitDivided(by: .minute()), days: days)
    }

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

    // MARK: - Body

    func latestWeight() async -> Double? {
        await latestQuantity(type: .bodyMass, unit: .gramUnit(with: .kilo))
    }

    // MARK: - Activity

    func averageSteps(days: Int) async -> Double? {
        guard isAvailable, days > 0 else { return nil }

        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: predicate),
            options: .cumulativeSum
        )

        do {
            let result = try await descriptor.result(for: store)
            guard let total = result?.sumQuantity()?.doubleValue(for: .count()) else { return nil }
            return total / Double(days)
        } catch {
            AppLog.healthKit.error("averageSteps query failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    // MARK: - Sleep

    func averageSleepHours(days: Int) async -> Double? {
        guard isAvailable else { return nil }

        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )

        do {
            let samples = try await descriptor.result(for: store)
            let asleepSamples = samples.filter { sample in
                let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                return value == .asleepCore || value == .asleepDeep || value == .asleepREM
            }
            guard !asleepSamples.isEmpty else { return nil }
            let totalSeconds = asleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            return totalSeconds / 3600.0 / Double(days)
        } catch {
            AppLog.healthKit.error("averageSleepHours query failed: \(error.localizedDescription, privacy: .private)")
            return nil
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
        let endDate = calendar.startOfDay(for: Date()).addingTimeInterval(86_400)
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return [] }

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

    private func latestQuantity(type: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard isAvailable else { return nil }

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(type))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )

        do {
            let samples = try await descriptor.result(for: store)
            return samples.first?.quantity.doubleValue(for: unit)
        } catch {
            AppLog.healthKit.error("latestQuantity \(type.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }
}
