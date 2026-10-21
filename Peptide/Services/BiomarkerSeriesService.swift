import Foundation

/// Builds `BiomarkerSnapshot`s for the Biology tab's biomarker
/// list. The list view asks for `snapshots(for:)` with the user's
/// chosen ordering; the service fans out to HealthKit (HRV / RHR
/// / sleep / steps / body temperature) and DataStore (weight log,
/// labs, manual body-composition entries) in parallel.
///
/// Trend math lives in this file so the view layer stays
/// presentation-only: "is this number going up or down" is a
/// decision, not a render.
///
/// The HealthKit-bound code paths can't be unit-tested without an
/// HKHealthStore mock (and Apple doesn't ship one), so this
/// service exposes the pure trend / change-text helpers
/// separately for direct testing.
@MainActor
enum BiomarkerSeriesService {

    static let windowDays: Int = 14
    /// Long-form window for detail-sheet charts. 90 days reads as
    /// "the last quarter" — long enough to see seasonal trends in
    /// HRV / RHR / weight without becoming a wall-of-data the
    /// user can't scan.
    static let detailWindowDays: Int = 90
    /// Minimum daily values before we'll call a trend direction.
    /// Below this we surface `.insufficient` instead of flipping
    /// up/down on two noisy readings.
    static let trendMinSamples: Int = 4
    /// Minimum samples before the row renders a sparkline. A single
    /// dot doesn't communicate a trajectory; below this we drop the
    /// sparkline so the row stays clean (audit Biology L20).
    static let sparklineMinSamples: Int = 2
    /// Relative change between window start and end below which
    /// we report `.flat` rather than `.up` / `.down`. Picked so a
    /// 0.3 kg weight fluctuation on a 70 kg user reads as flat
    /// (~0.4%, below threshold) and a 1.5 kg drift reads as a
    /// direction.
    static let trendFlatThreshold: Double = 0.015

    /// Build snapshots for the requested biomarkers in the
    /// requested order. Each biomarker is fetched independently and
    /// in parallel — a typical refresh fans out 4-5 HealthKit
    /// queries, and the serial loop made the total latency the sum
    /// rather than the max. Missing data degrades to `.empty(biomarker)`
    /// instead of blocking the rest.
    static func snapshots(
        for biomarkers: [Biomarker],
        weightHistory: [WeightEntry],
        latestLab: LabValue?,
        days: Int = windowDays,
        unit: MeasurementUnit = .metric
    ) async -> [BiomarkerSnapshot] {
        await withTaskGroup(of: (Int, BiomarkerSnapshot).self) { group in
            for (index, biomarker) in biomarkers.enumerated() {
                group.addTask {
                    let snap = await snapshot(
                        for: biomarker,
                        weightHistory: weightHistory,
                        latestLab: latestLab,
                        days: days,
                        unit: unit
                    )
                    return (index, snap)
                }
            }
            // Reassemble in the requested order — TaskGroup yields in
            // completion order, but callers rely on a stable index.
            var collected: [(Int, BiomarkerSnapshot)] = []
            collected.reserveCapacity(biomarkers.count)
            for await pair in group { collected.append(pair) }
            collected.sort { $0.0 < $1.0 }
            return collected.map(\.1)
        }
    }

    private static func snapshot(
        for biomarker: Biomarker,
        weightHistory: [WeightEntry],
        latestLab: LabValue?,
        days: Int,
        unit: MeasurementUnit
    ) async -> BiomarkerSnapshot {
        switch biomarker {
        case .weight:
            return weightSnapshot(weightHistory: weightHistory, days: days, unit: unit)
        case .hrvBaseline:
            let series = await HealthKitService.shared.dailyHRV(days: days)
            return seriesSnapshot(.hrvBaseline, series: series, unit: unit)
        case .rhrBaseline:
            let series = await HealthKitService.shared.dailyRestingHeartRate(days: days)
            return seriesSnapshot(.rhrBaseline, series: series, unit: unit)
        case .sleepBaseline:
            let series = await HealthKitService.shared.dailySleepHours(days: days)
            return seriesSnapshot(.sleepBaseline, series: series, unit: unit)
        case .stepsBaseline:
            let series = await HealthKitService.shared.dailySteps(days: days)
            return seriesSnapshot(.stepsBaseline, series: completedDays(series), unit: unit)
        case .bodyTemperature, .bodyFat, .waist, .bloodPressure:
            // Manual-entry biomarkers — Pro-gated, persistence
            // surface lands in a follow-up commit. Tile renders
            // an "Add" CTA when empty.
            return .empty(biomarker)
        case .latestLabPanel:
            return labSnapshot(latestLab: latestLab)
        }
    }

    // MARK: - Per-source builders

    /// Pulls the WeightEntry samples from the last `days` calendar
    /// days, one per day (the latest weigh-in that day), so a log
    /// that stopped months ago doesn't read as a current trend
    /// (kilograms is the canonical storage unit on UserProfile).
    /// Trend math runs over the actual sequence, not just first vs
    /// last — a single outlier shouldn't flip the direction.
    static func weightSnapshot(
        weightHistory: [WeightEntry],
        days: Int = windowDays,
        unit: MeasurementUnit = .metric,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BiomarkerSnapshot {
        let startOfToday = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: 1 - days, to: startOfToday) else {
            return .empty(.weight)
        }
        var latestPerDay: [Date: WeightEntry] = [:]
        for entry in weightHistory where entry.date >= windowStart {
            let day = calendar.startOfDay(for: entry.date)
            if let kept = latestPerDay[day], kept.date >= entry.date { continue }
            latestPerDay[day] = entry
        }
        let recent = latestPerDay.values
            .sorted { $0.date < $1.date }
            .map { BiomarkerSnapshot.Sample(date: $0.date, value: $0.kg) }
        guard let latest = recent.last?.value else { return .empty(.weight) }
        let trend = inferTrend(samples: recent.map(\.value))
        return BiomarkerSnapshot(
            biomarker: .weight,
            latest: latest,
            trend: trend,
            samples: recent.count >= sparklineMinSamples ? recent : [],
            changeText: changeText(for: .weight, trend: trend, latest: latest, unit: unit)
        )
    }

    /// Generic series → snapshot for the HealthKit-backed
    /// biomarkers (HRV / RHR / sleep). All three follow the same
    /// shape: 14 daily values, latest is the most recent, trend
    /// reads from the whole series.
    static func seriesSnapshot(
        _ biomarker: Biomarker,
        series: [(date: Date, value: Double)],
        unit: MeasurementUnit = .metric
    ) -> BiomarkerSnapshot {
        guard let latest = series.last?.value else { return .empty(biomarker) }
        let trend = inferTrend(samples: series.map(\.value))
        return BiomarkerSnapshot(
            biomarker: biomarker,
            latest: latest,
            trend: trend,
            samples: series.count >= sparklineMinSamples
                ? series.map { BiomarkerSnapshot.Sample(date: $0.date, value: $0.value) }
                : [],
            changeText: changeText(for: biomarker, trend: trend, latest: latest, unit: unit)
        )
    }

    /// Drops today's bucket from a cumulative series. Steps add up
    /// through the day, so a morning's 812 as `latest` read as
    /// "Less active" and dragged the trend down every day.
    static func completedDays(
        _ series: [(date: Date, value: Double)],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [(date: Date, value: Double)] {
        let startOfToday = calendar.startOfDay(for: now)
        return series.filter { $0.date < startOfToday }
    }

    static func labSnapshot(latestLab: LabValue?) -> BiomarkerSnapshot {
        guard let lab = latestLab else { return .empty(.latestLabPanel) }
        // The lab tile renders the panel name + value + unit
        // (e.g. "Total testosterone · 720 ng/dL") rather than a
        // verb. Trend is intentionally insufficient — labs are
        // sparse-on-purpose; a real lab-trend chart belongs in
        // BiomarkerDetailSheet (commit 8), not the row.
        let unit = lab.panel.canonicalUnit
        let valueStr = LabValueFormat.string(lab.value)
        return BiomarkerSnapshot(
            biomarker: .latestLabPanel,
            latest: lab.value,
            trend: .insufficient,
            samples: [],
            changeText: "\(lab.panel.displayName) · \(valueStr) \(unit)"
        )
    }

    // MARK: - Pure helpers (testable)

    /// Trend inference. Splits the series in half, compares the
    /// medians, and applies the flat-threshold filter so the
    /// trend doesn't flip on every tiny shift. Returns
    /// `.insufficient` for series shorter than `trendMinSamples`.
    static func inferTrend(samples: [Double]) -> BiomarkerSnapshot.Trend {
        guard samples.count >= trendMinSamples else { return .insufficient }
        let half = samples.count / 2
        let firstHalf  = Array(samples.prefix(half))
        let secondHalf = Array(samples.suffix(samples.count - half))
        guard let firstMedian = median(firstHalf), firstMedian > 0,
              let secondMedian = median(secondHalf)
        else { return .insufficient }
        let relativeChange = (secondMedian - firstMedian) / firstMedian
        if abs(relativeChange) < trendFlatThreshold { return .flat }
        return relativeChange > 0 ? .up : .down
    }

    /// Median over a Double series. `nil` when empty so callers
    /// can short-circuit. Used by `inferTrend` because medians
    /// resist a single outlier (a one-off 80 kg weigh-in after
    /// 14 days at 72 kg won't flip the direction).
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    /// Pre-formatted "verb · value" subtitle the row consumes.
    /// Localized + biomarker-aware so a flat HRV reads as
    /// "Steady · 58 ms" while a flat weight reads as
    /// "Holding · 72.0 kg". Tiny copy variants, but the polish
    /// is what makes the screen feel premium.
    static func changeText(
        for biomarker: Biomarker,
        trend: BiomarkerSnapshot.Trend,
        latest: Double,
        unit: MeasurementUnit = .metric
    ) -> String {
        // `latest` is stored canonical metric; convert to the user's unit
        // for display (kg→lb, cm→in, °C→°F). HRV/RHR/sleep/steps are
        // unit-agnostic, so displayValue returns them unchanged.
        let formatted = formatValue(biomarker.displayValue(latest, for: unit), for: biomarker)
        let verb: String
        switch (biomarker, trend) {
        case (.weight, .up):           verb = String(localized: "Increasing")
        case (.weight, .down):         verb = String(localized: "Decreasing")
        case (.weight, .flat):         verb = String(localized: "Holding")
        case (.hrvBaseline, .up):      verb = String(localized: "Trending up")
        case (.hrvBaseline, .down):    verb = String(localized: "Trending down")
        case (.hrvBaseline, .flat):    verb = String(localized: "Steady")
        case (.rhrBaseline, .up):      verb = String(localized: "Higher")
        case (.rhrBaseline, .down):    verb = String(localized: "Lower")
        case (.rhrBaseline, .flat):    verb = String(localized: "Steady")
        case (.sleepBaseline, .up):    verb = String(localized: "More sleep")
        case (.sleepBaseline, .down):  verb = String(localized: "Less sleep")
        case (.sleepBaseline, .flat):  verb = String(localized: "Consistent")
        case (.stepsBaseline, .up):    verb = String(localized: "More active")
        case (.stepsBaseline, .down):  verb = String(localized: "Less active")
        case (.stepsBaseline, .flat):  verb = String(localized: "Steady")
        default:                        verb = String(localized: "Latest")
        }
        if let unitString = biomarker.displayUnit(for: unit) {
            return "\(verb) · \(formatted) \(unitString)"
        }
        return "\(verb) · \(formatted)"
    }

    /// Biomarker-specific number formatting. Weight is one
    /// decimal, HRV / RHR / steps are integers, sleep is one
    /// decimal in hours. Keeps the view from doing this math.
    static func formatValue(_ value: Double, for biomarker: Biomarker) -> String {
        switch biomarker {
        case .weight, .sleepBaseline, .bodyTemperature, .bodyFat:
            return value.formatted(.number.precision(.fractionLength(1)))
        case .hrvBaseline, .rhrBaseline, .stepsBaseline, .waist, .bloodPressure:
            return value.formatted(.number.precision(.fractionLength(0)))
        case .latestLabPanel:
            return LabValueFormat.string(value)
        }
    }
}
