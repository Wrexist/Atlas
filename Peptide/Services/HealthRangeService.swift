import Foundation

/// Builds Bevel-style personal-range snapshots for the Health
/// Monitor grid on Today. For each metric — HRV, RHR, Sleep — pulls
/// daily values over a 21-day window from HealthKit, computes the
/// p10 / p25 / p75 / p90 quartiles, and pairs them with the most
/// recent reading so the BiometricCard can render "where today sits
/// in my own range" instead of an absolute number alone.
///
/// 21 days is a sweet spot: long enough to capture weekly variation
/// (training-heavy days vs rest days) without diluting recent
/// shifts the way a 90-day baseline would. Matches what Bevel /
/// Whoop / Oura use for the same kind of "today vs you" overlay.
@MainActor
enum HealthRangeService {

    /// Direction in which "higher" means "better health" for a
    /// metric. Drives the status-pill colouring downstream: HRV
    /// higher = green, RHR higher = blue/cautionary, Sleep higher
    /// = green within reason.
    enum Direction: Equatable, Sendable {
        case higherIsBetter, lowerIsBetter, neutral
    }

    enum Status: Equatable, Sendable {
        case lower, normal, higher
    }

    /// One metric's full snapshot. `latest` is the most recent
    /// reading; `range` is the user's personal 21-day spread. The
    /// view layer maps `status` to a colour + label
    /// ("Lower" / "Normal" / "Higher").
    struct Sample: Equatable, Sendable {
        let latest: Double
        let p10: Double
        let p25: Double
        let p75: Double
        let p90: Double
        let direction: Direction
        /// How much history this personal range is actually built on —
        /// see `BaselineConfidence`. Defaults to `.establishedBaseline`
        /// only so existing call sites (previews, tests) that construct a
        /// `Sample` directly with a full, presumed-trustworthy range keep
        /// compiling; `sample(from:direction:)` always computes the real
        /// value from the series it was given.
        var confidence: BaselineConfidence = .establishedBaseline

        /// A short, honest hedge to pair with the status pill — `nil`
        /// when the pill already says everything worth saying.
        /// Personalization brief Phase 3: a baseline "must not appear
        /// equally reliable" for a brand-new range and a fully-
        /// established one, so an emerging range gets an explicit
        /// caption; an established one doesn't repeat itself, and Phase
        /// 17 says not to keep harping on "still learning" once it stops
        /// being true.
        var confidenceCaption: String? {
            switch confidence {
            case .establishedBaseline, .insufficientHistory:
                return nil
            case .emergingBaseline:
                return "Early read — still learning your range"
            }
        }

        /// Where the latest value sits relative to the user's
        /// p25–p75 interquartile band. Anything inside the IQR is
        /// "normal"; below p25 is "lower"; above p75 is "higher".
        var status: Status {
            // Guard a degenerate IQR: with near-identical readings
            // p25 == p75, so any tiny deviation would otherwise flip
            // the pill to Lower/Higher off pure noise. A collapsed
            // band reads as Normal. (positionInRange already guards
            // its own p10–p90 span.)
            guard p75 - p25 > 0.0001 else { return .normal }
            if latest < p25 { return .lower }
            if latest > p75 { return .higher }
            return .normal
        }

        /// 0…1 fraction along the p10–p90 range where the latest
        /// reading lives. Drives the vertical range indicator's dot
        /// position. Clamped so out-of-range values pin to the ends.
        var positionInRange: Double {
            let span = p90 - p10
            guard span > 0 else { return 0.5 }
            return max(0, min(1, (latest - p10) / span))
        }
    }

    struct Snapshot: Equatable, Sendable {
        let hrv: Sample?
        let rhr: Sample?
        let sleep: Sample?
    }

    /// Builds the snapshot. Each metric is pulled in parallel via
    /// `async let` so a fresh open of Today doesn't pay 3× the
    /// HealthKit round-trip latency. Each metric independently
    /// returns nil when fewer than `minSampleCount` daily values
    /// exist — the grid hides cards that can't be meaningfully
    /// rendered rather than showing a misleading "all at the
    /// midpoint" fallback.
    static let windowDays: Int = 21
    static let minSampleCount: Int = 7

    static func build() async -> Snapshot {
        let kit = HealthKitService.shared
        async let hrv   = sample(from: kit.dailyHRV(days: windowDays),               direction: .higherIsBetter)
        async let rhr   = sample(from: kit.dailyRestingHeartRate(days: windowDays),  direction: .lowerIsBetter)
        async let sleep = sample(from: kit.dailySleepHours(days: windowDays),        direction: .higherIsBetter)
        return await Snapshot(hrv: hrv, rhr: rhr, sleep: sleep)
    }

    // MARK: - Internals

    static func sample(
        from series: [(date: Date, value: Double)],
        direction: Direction
    ) -> Sample? {
        guard series.count >= minSampleCount else { return nil }

        let latest = series.max(by: { $0.date < $1.date })?.value ?? series.last?.value ?? 0

        // `emergingAt` is deliberately the same `minSampleCount` gate this
        // function already required to return non-nil at all — a snapshot
        // this method is willing to show is never itself "insufficient."
        // `establishedAt` is the full `windowDays` window: nothing short of
        // the full 21-day target reads as a fully-trusted personal range.
        guard let baseline = PersonalBaselineEngine.build(
            values: series.map(\.value),
            emergingAt: minSampleCount,
            establishedAt: windowDays
        ) else { return nil }

        return Sample(
            latest: latest,
            p10: baseline.p10,
            p25: baseline.p25,
            p75: baseline.p75,
            p90: baseline.p90,
            direction: direction,
            confidence: baseline.confidence
        )
    }

    /// Nearest-rank percentile — simple, doesn't interpolate, gives
    /// stable results for the small samples (7–21 days) we work
    /// with. Linear interpolation would over-smooth values that
    /// real users would expect to land on an actual day's reading.
    /// Forwards to `PersonalBaselineEngine`'s identical formula so the
    /// two personal-range implementations can't silently drift apart.
    static func percentile(_ sortedValues: [Double], _ p: Double) -> Double {
        PersonalBaselineEngine.percentile(sortedValues, p)
    }
}
