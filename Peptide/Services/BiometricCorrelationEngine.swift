import Foundation

/// Compares HealthKit biometric daily series (HRV, RHR, sleep)
/// against the user's dose-day flag. Sibling to
/// `OutcomeCorrelationEngine` — same on-day-vs-off-day shape, but
/// over biometric streams instead of self-reported scores.
///
/// Returns the strongest *positive* correlation as the headline
/// surface — "your HRV is 8 ms higher on dosing days" is the
/// kind of insight that justifies the whole HealthKit integration.
/// Sample-size + effect-size guards keep the engine from surfacing
/// noise during the first week of an install.
enum BiometricCorrelationEngine {

    /// Three biometric streams the Apple Watch / iPhone reliably
    /// surface for the optimisation cohort. Each carries display
    /// name + unit + the canonical "more is better" direction so
    /// the headline can render "+X higher" or "-X lower" with the
    /// right valence.
    enum Metric: String, CaseIterable, Identifiable, Sendable {
        case hrv
        case restingHeartRate
        case sleep

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .hrv:               String(localized: "HRV")
            case .restingHeartRate:  String(localized: "Resting heart rate")
            case .sleep:             String(localized: "Sleep")
            }
        }

        var unit: String {
            switch self {
            case .hrv:               "ms"
            case .restingHeartRate:  "bpm"
            case .sleep:             "h"
            }
        }

        /// `true` when a higher value is better (HRV, sleep);
        /// `false` when lower is better (RHR). Drives the headline
        /// copy: a +5 bpm RHR delta on dosing days is *bad* news,
        /// a +5 ms HRV delta is *good* news.
        var higherIsBetter: Bool {
            switch self {
            case .hrv, .sleep:       true
            case .restingHeartRate:  false
            }
        }

        /// Magnitude floor below which a delta is considered noise
        /// and not surfaced. Tuned per metric: HRV swings 2-3 ms
        /// day to day naturally, RHR ±2 bpm, sleep ±0.5 h.
        var noiseFloor: Double {
            switch self {
            case .hrv:               4.0
            case .restingHeartRate:  3.0
            case .sleep:             0.5
            }
        }
    }

    /// One result row. `delta` is signed (on-dose-day minus
    /// off-dose-day). `isFavourable` resolves the sign against the
    /// metric's `higherIsBetter` so the headline can use one branch
    /// regardless of metric.
    struct Finding: Equatable, Sendable {
        let metric: Metric
        let onDoseDays: Double
        let offDoseDays: Double
        let doseDayCount: Int
        let offDayCount: Int

        var delta: Double { onDoseDays - offDoseDays }

        var isFavourable: Bool {
            metric.higherIsBetter ? delta > 0 : delta < 0
        }

        var absoluteEffect: Double { abs(delta) }
    }

    /// Minimum days in each bucket. Same threshold as
    /// `OutcomeCorrelationEngine.minimumSamplesPerBucket` so the
    /// two engines surface their first insights at the same time.
    static let minimumSamplesPerBucket = 4

    /// Per-metric correlation. `nil` per metric when either bucket
    /// is empty. Caller picks the headline via `headline(in:)` or
    /// renders the full table.
    static func correlations(
        seriesByMetric: [Metric: [(date: Date, value: Double)]],
        entries: [ProtocolEntry]
    ) -> [Finding] {
        let calendar = Calendar.current
        let dosedDays: Set<Date> = Set(
            entries
                .filter(\.completed)
                .map { calendar.startOfDay(for: $0.date) }
        )
        guard !dosedDays.isEmpty else { return [] }

        return Metric.allCases.compactMap { metric in
            guard let series = seriesByMetric[metric], !series.isEmpty else {
                return nil
            }
            let (on, off) = series.partition { sample in
                dosedDays.contains(calendar.startOfDay(for: sample.date))
            }
            guard let onMedian = median(on.map(\.value)),
                  let offMedian = median(off.map(\.value)),
                  on.count >= minimumSamplesPerBucket,
                  off.count >= minimumSamplesPerBucket
            else { return nil }
            return Finding(
                metric: metric,
                onDoseDays: onMedian,
                offDoseDays: offMedian,
                doseDayCount: on.count,
                offDayCount: off.count
            )
        }
    }

    /// Picks the single most favourable finding to surface as a
    /// headline. Sorts by absolute effect descending after filtering
    /// to favourable-direction only. Returns nil when nothing
    /// meaningful surfaced.
    static func headline(from findings: [Finding]) -> Finding? {
        let qualified = findings.filter { finding in
            finding.isFavourable
                && finding.absoluteEffect >= finding.metric.noiseFloor
        }
        return qualified.max { $0.absoluteEffect < $1.absoluteEffect }
    }

    /// Median, not mean: a single sick-day / travel-day outlier in HRV or
    /// RHR shouldn't flip an on-vs-off-dose finding's direction. Matches
    /// the rest of the correlation pipeline.
    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

private extension Array {
    /// Same partition helper as `OutcomeCorrelationEngine`. Kept
    /// fileprivate to each consumer rather than promoted to a
    /// shared utility because both call sites are local + the
    /// helper is one screenful.
    func partition(by belongsInFirst: (Element) -> Bool) -> ([Element], [Element]) {
        var first: [Element] = []
        var second: [Element] = []
        first.reserveCapacity(count)
        for element in self {
            if belongsInFirst(element) { first.append(element) } else { second.append(element) }
        }
        return (first, second)
    }
}
