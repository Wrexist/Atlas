import Foundation

/// Whether today's suggested loads should change, from last night's sleep
/// and HRV / resting heart rate against the user's own baseline. Reads the
/// same `RecoveryScoreEngine.Inputs` as the Today screen's Recovery %, so
/// the workout and the dashboard look at the same numbers. Missing data
/// never counts against the user: no reading means a normal day.
enum ReadinessEngine {

    enum Level: String, Codable, Equatable, Sendable {
        case ready, normal, low
    }

    enum Reason: String, Codable, Equatable, Sendable {
        case hrvBelowBaseline
        case restingHeartRateAboveBaseline
        case shortSleep
        case hrvAboveBaseline
        case typical
        case noData
    }

    struct Assessment: Codable, Equatable, Sendable {
        let level: Level
        let reason: Reason

        static let unknown = Assessment(level: .normal, reason: .noData)
    }

    /// HRV this far under baseline is a recovery deficit, not day-to-day noise.
    static let lowHRVRatio = 0.85
    static let highHRVRatio = 1.05
    /// Resting heart rate moves less than HRV, so a smaller rise counts.
    static let highRHRRatio = 1.07
    static let shortSleepHours = 6.0
    static let restedSleepHours = 7.0

    /// The first deficit found decides the reason; HRV leads because it's
    /// the strongest of the three signals.
    static func assess(_ inputs: RecoveryScoreEngine.Inputs) -> Assessment {
        let hrv = ratio(inputs.recentHRV, to: inputs.baselineHRV)
        let rhr = ratio(inputs.recentRHR, to: inputs.baselineRHR)
        let sleep = inputs.lastSleepHours.flatMap { $0 > 0 ? $0 : nil }
        if hrv == nil, rhr == nil, sleep == nil { return .unknown }

        if let hrv, hrv < lowHRVRatio { return Assessment(level: .low, reason: .hrvBelowBaseline) }
        if let rhr, rhr > highRHRRatio { return Assessment(level: .low, reason: .restingHeartRateAboveBaseline) }
        if let sleep, sleep < shortSleepHours { return Assessment(level: .low, reason: .shortSleep) }
        if let hrv, hrv >= highHRVRatio, (sleep ?? restedSleepHours) >= restedSleepHours {
            return Assessment(level: .ready, reason: .hrvAboveBaseline)
        }
        return Assessment(level: .normal, reason: .typical)
    }

    /// An assessment that came from real Health data, and when.
    struct Reading: Codable, Equatable, Sendable {
        let assessment: Assessment
        let measuredAt: Date
    }

    /// Keep-last-good: Health answers every read with nothing while the
    /// device is locked, which `assess` turns into `.unknown`. An empty read
    /// therefore never replaces a reading taken earlier the same day; a
    /// reading from an earlier day is not today's readiness and is dropped.
    static func retained(fresh: Assessment, last: Reading?, now: Date, calendar: Calendar) -> Assessment {
        guard fresh.reason == .noData, let last, calendar.isDate(last.measuredAt, inSameDayAs: now) else {
            return fresh
        }
        return last.assessment
    }

    private static func ratio(_ recent: Double?, to baseline: Double?) -> Double? {
        guard let recent, let baseline, recent > 0, baseline > 0 else { return nil }
        return recent / baseline
    }
}
