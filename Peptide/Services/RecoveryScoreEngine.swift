import Foundation

/// Composite "are you recovered?" score for the Today hero trio.
/// Pure value-in / value-out so it's trivial to unit-test against
/// known HRV / RHR / sleep inputs without standing up HealthKit.
///
/// Bevel surfaces a single Recovery % derived from sleep + HRV + RHR.
/// Mirroring that shape here keeps the dashboard's mental model
/// portable: a user familiar with Whoop / Oura / Bevel can read
/// Atlas's number without re-learning what "recovery" means.
///
/// Component weights are tuned (not learned). HRV and Sleep both
/// dominate because they're the highest-signal recovery indicators
/// in the literature for sub-clinical training contexts; RHR is a
/// secondary tiebreaker that catches "I slept fine, HRV is fine, but
/// my heart is racing today" cases.
enum RecoveryScoreEngine {

    /// Final score returned to the UI. 0…100 (Int) is the user-facing
    /// number; `components` is included so the detail sheet can
    /// surface "your HRV is up, your sleep is short" without
    /// recomputing.
    struct Score: Equatable, Sendable {
        let value: Int                          // 0…100
        let components: Components
        /// True when at least one input was missing — UI may want to
        /// nudge the user to connect HealthKit or wear their watch.
        let isPartialData: Bool
    }

    struct Components: Equatable, Sendable {
        let hrv: Double?                        // 0…1, nil = no data
        let sleep: Double?                      // 0…1
        let rhr: Double?                        // 0…1
    }

    struct Inputs: Equatable, Sendable {
        /// Recent HRV reading (ms). Typically `averageHRV(days: 3)`.
        let recentHRV: Double?
        /// Baseline HRV (ms) over a longer window — typically
        /// `averageHRV(days: 30)`.
        let baselineHRV: Double?
        /// Recent resting heart rate (bpm). Lower-is-better for the
        /// score, so the engine inverts before composing.
        let recentRHR: Double?
        /// Baseline resting heart rate (bpm).
        let baselineRHR: Double?
        /// Last sleep session duration in hours.
        let lastSleepHours: Double?
        /// Optional override of the sleep target. Defaults to 8h —
        /// the typical floor at which recovery curves plateau.
        let sleepTargetHours: Double

        init(
            recentHRV: Double? = nil,
            baselineHRV: Double? = nil,
            recentRHR: Double? = nil,
            baselineRHR: Double? = nil,
            lastSleepHours: Double? = nil,
            sleepTargetHours: Double = 8.0
        ) {
            self.recentHRV = recentHRV
            self.baselineHRV = baselineHRV
            self.recentRHR = recentRHR
            self.baselineRHR = baselineRHR
            self.lastSleepHours = lastSleepHours
            self.sleepTargetHours = sleepTargetHours
        }
    }

    // MARK: - Weights
    //
    // Sum to 1.0 when all three components are present. When a
    // component is nil, its weight is redistributed proportionally
    // across the available components — so a user with sleep + HRV
    // but no RHR still gets a meaningful score, scaled by the inputs
    // we actually have rather than penalised for missing data.

    private static let hrvWeight: Double   = 0.45
    private static let sleepWeight: Double = 0.40
    private static let rhrWeight: Double   = 0.15

    /// Below this fraction of baseline HRV, the score floor for HRV
    /// kicks in (0). Above 1.2× baseline, the ceiling caps at 1.0 so
    /// a transient PNS spike from a calm morning doesn't peg the
    /// score at 100 and hide further drift.
    private static let hrvFloor: Double = 0.70
    private static let hrvCeiling: Double = 1.20

    /// RHR is inverted before scoring. ±15% from baseline maps to
    /// the 0…1 range — wider than HRV because RHR moves slower and
    /// in smaller relative amounts.
    private static let rhrFloor: Double = 0.85    // 15% lower than baseline → score 1.0
    private static let rhrCeiling: Double = 1.15  // 15% higher than baseline → score 0.0

    // MARK: - Public

    static func score(inputs: Inputs) -> Score? {
        let hrv   = hrvComponent(recent: inputs.recentHRV,   baseline: inputs.baselineHRV)
        let sleep = sleepComponent(hours: inputs.lastSleepHours, target: inputs.sleepTargetHours)
        let rhr   = rhrComponent(recent: inputs.recentRHR,   baseline: inputs.baselineRHR)

        let weighted = weightedAverage(hrv: hrv, sleep: sleep, rhr: rhr)
        guard let weighted else { return nil }   // no inputs at all

        // Only treat as partial when the user is missing one of the
        // two cardio signals (HRV / RHR). A nil sleep is common —
        // plenty of users don't wear their Watch to bed — and dimming
        // the score badge every morning for them is a false alarm
        // (audit Biology L16). Tradeoff: a user with sleep alone (no
        // HRV/RHR, e.g. a manual sleep logger) still gets flagged so
        // they can see the upgrade nudge.
        let isPartial = (hrv == nil) || (rhr == nil)
        return Score(
            value: Int((weighted * 100).rounded()),
            components: Components(hrv: hrv, sleep: sleep, rhr: rhr),
            isPartialData: isPartial
        )
    }

    // MARK: - Components

    /// Maps today's HRV against the user's own baseline. A value of
    /// 1.0 here means "as good as your typical recent baseline";
    /// values above 1.0 saturate because we don't want a single
    /// great-sleep morning to mask a developing trend in the other
    /// inputs.
    static func hrvComponent(recent: Double?, baseline: Double?) -> Double? {
        guard let recent, let baseline, baseline > 0 else { return nil }
        let ratio = recent / baseline
        let normalised = (ratio - hrvFloor) / (hrvCeiling - hrvFloor)
        return max(0, min(1, normalised))
    }

    /// Linear ramp from 0 → target hours. Mathematically simple on
    /// purpose: any sleep coach app's deeper model (REM ratios, sleep
    /// debt) would belong in a dedicated Sleep service, not the
    /// composite recovery score.
    static func sleepComponent(hours: Double?, target: Double) -> Double? {
        guard let hours, target > 0 else { return nil }
        return max(0, min(1, hours / target))
    }

    /// RHR is inverted: lower vs baseline = better recovery. Same
    /// floor/ceiling structure as HRV but tighter bounds because RHR
    /// is naturally less variable.
    static func rhrComponent(recent: Double?, baseline: Double?) -> Double? {
        guard let recent, let baseline, baseline > 0 else { return nil }
        let ratio = recent / baseline
        // ratio < 1 means RHR is lower than baseline (good).
        // ratio > 1 means RHR is higher (bad).
        let inverted = 1 - (ratio - rhrFloor) / (rhrCeiling - rhrFloor)
        return max(0, min(1, inverted))
    }

    // MARK: - Weighting

    /// Weighted average over the available components. Returns nil
    /// only when every component is nil — partial data is still
    /// scored, with the missing component's weight redistributed
    /// across the present ones.
    private static func weightedAverage(hrv: Double?, sleep: Double?, rhr: Double?) -> Double? {
        var totalWeight: Double = 0
        var weighted: Double = 0
        if let hrv {
            weighted += hrv * hrvWeight
            totalWeight += hrvWeight
        }
        if let sleep {
            weighted += sleep * sleepWeight
            totalWeight += sleepWeight
        }
        if let rhr {
            weighted += rhr * rhrWeight
            totalWeight += rhrWeight
        }
        guard totalWeight > 0 else { return nil }
        return weighted / totalWeight
    }
}
