import Foundation

/// Pure-function correlation analysis between outcome check-ins
/// (`OutcomeEntry`) and peptide dose adherence (`ProtocolEntry`).
/// Answers "do my wellness scores trend better on dosing days?"
/// without hitting a network — the math is small and deterministic
/// so we run it locally on every render and let the cache layer in
/// the view memoise results if needed.
///
/// Two output shapes:
///
///   • `DimensionCorrelation` — per-dimension delta between days the
///     user took at least one dose and days they didn't. Surfaces
///     the most striking numbers ("sleep is 0.6 points higher on
///     dosing days") as headline insights.
///   • `TrendPoint` — daily composite score with overlaid dose-day
///     marker. Drives the timeline visualisation.
///
/// Sample-size guards throughout: a single dosing day's worth of
/// data isn't enough to draw any conclusion. Callers get nil from
/// `headline(for:in:)` until both sides cross a minimum threshold.
enum OutcomeCorrelationEngine {

    /// Minimum days in each bucket (dose / no-dose) before a
    /// per-dimension delta is allowed to surface as a headline
    /// insight. Small enough to engage early adopters, large enough
    /// to filter out coincidence.
    static let minimumSamplesPerBucket = 4

    /// Magnitude (in 1-5 score points) below which a delta is
    /// considered noise. 0.3 is roughly the standard error of a
    /// single self-rating on a 1-5 scale, so anything below this
    /// shouldn't be surfaced as a real trend.
    static let minimumMeaningfulDelta: Double = 0.3

    // MARK: - Per-dimension comparison

    struct DimensionCorrelation: Equatable, Sendable {
        let dimension: OutcomeDimension
        /// Average score on days the user logged at least one
        /// completed dose. nil when there's no data.
        let onDoseDays: Double?
        /// Average score on days the user logged no completed doses.
        let offDoseDays: Double?
        let doseDayCount: Int
        let offDayCount: Int

        /// `onDoseDays − offDoseDays`. Positive = doses correlate
        /// with feeling better; negative = doses correlate with
        /// feeling worse (or are confounded by side effects).
        var delta: Double? {
            guard let on = onDoseDays, let off = offDoseDays else { return nil }
            return on - off
        }

        /// True when both buckets have enough samples to be
        /// statistically interesting. The threshold is intentionally
        /// modest so a user who's been at it for two weeks sees
        /// preliminary signal.
        var hasEnoughData: Bool {
            doseDayCount >= OutcomeCorrelationEngine.minimumSamplesPerBucket
                && offDayCount >= OutcomeCorrelationEngine.minimumSamplesPerBucket
        }
    }

    /// Splits the outcome history into "dosing day" and "no-dose
    /// day" buckets (by `ProtocolEntry.completed`), averages each
    /// dimension, returns the comparison for every dimension.
    static func dimensionCorrelations(
        outcomes: [OutcomeEntry],
        entries: [ProtocolEntry]
    ) -> [DimensionCorrelation] {
        let calendar = Calendar.current
        let dosedDays: Set<Date> = Set(
            entries
                .filter(\.completed)
                .map { calendar.startOfDay(for: $0.date) }
        )

        // Split outcomes once, then iterate dimensions over the
        // split — avoids walking the outcomes list five times.
        let (dosed, undosed) = outcomes.partition { entry in
            dosedDays.contains(calendar.startOfDay(for: entry.date))
        }

        return OutcomeDimension.allCases.map { dim in
            let onAvg = average(dosed.map { Double(dim.value(in: $0)) })
            let offAvg = average(undosed.map { Double(dim.value(in: $0)) })
            return DimensionCorrelation(
                dimension: dim,
                onDoseDays: onAvg,
                offDoseDays: offAvg,
                doseDayCount: dosed.count,
                offDayCount: undosed.count
            )
        }
    }

    /// Picks the most striking *positive* correlation across the
    /// dimensions, returning nil when no dimension meets the
    /// sample-size + magnitude bar. Powers the headline "Your sleep
    /// is X points higher on dosing days" surface.
    static func headline(
        outcomes: [OutcomeEntry],
        entries: [ProtocolEntry]
    ) -> DimensionCorrelation? {
        let correlations = dimensionCorrelations(outcomes: outcomes, entries: entries)
        let candidates = correlations
            .filter(\.hasEnoughData)
            .filter { ($0.delta ?? 0) >= minimumMeaningfulDelta }
        // Sort by delta descending so the strongest positive
        // correlation wins. Ties broken arbitrarily but stably.
        return candidates.max { ($0.delta ?? 0) < ($1.delta ?? 0) }
    }

    // MARK: - Timeline points

    struct TrendPoint: Equatable, Sendable {
        let date: Date
        let composite: Double
        let onDoseDay: Bool
    }

    /// Daily composite-score points for the last `days` days. Days
    /// without a check-in are skipped (rather than zero-filled) so
    /// the chart shows real data, not a misleading gap-as-zero.
    static func trendPoints(
        outcomes: [OutcomeEntry],
        entries: [ProtocolEntry],
        days: Int
    ) -> [TrendPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let cutoff = calendar.date(byAdding: .day, value: -days + 1, to: today) else { return [] }
        let dosedDays: Set<Date> = Set(
            entries
                .filter(\.completed)
                .map { calendar.startOfDay(for: $0.date) }
        )
        return outcomes
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
            .map { entry in
                TrendPoint(
                    date: entry.date,
                    composite: entry.composite,
                    onDoseDay: dosedDays.contains(calendar.startOfDay(for: entry.date))
                )
            }
    }

    // MARK: - Helpers

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

private extension Array {
    /// In-pass partition that returns two arrays (matches / rest).
    /// Stdlib's `partition(by:)` mutates the array in place and
    /// returns a pivot index; this variant is friendlier for the
    /// downstream `[Element]` consumers in `dimensionCorrelations`.
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
