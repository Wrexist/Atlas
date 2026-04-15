import Foundation
import HealthKit
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
    @ObservationIgnored private var activeQueries: [HKObserverQuery] = []
    private(set) var cachedSnapshot: HealthSnapshot?
    private var isBackgroundDeliveryStarted = false

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
        for query in activeQueries { store.stop(query) }
        activeQueries.removeAll()
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
            return  // Simulator or authorization not granted — skip silently
        }

        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completionHandler, error in
            // Call immediately — our refresh runs in a separate Task per Apple's guidance
            completionHandler()
            guard error == nil else { return }
            Task { @MainActor [weak self] in
                await self?.refreshSnapshot()
            }
        }
        store.execute(query)
        activeQueries.append(query)
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
            return nil
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
            return nil
        }
    }
}
