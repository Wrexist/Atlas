import Foundation

/// The Biology tab's sleep deep-dive: two weeks of nights reduced to the
/// handful of numbers that explain them — how long, how efficiently, in
/// which stages, how regular the clock is, and how far behind the target
/// the last week left you. Pure value-in / value-out so it tests without
/// HealthKit.
enum SleepInsightsEngine {

    struct StageShares: Equatable, Sendable {
        let deep: Double
        let core: Double
        let rem: Double
    }

    enum Consistency: Equatable, Sendable {
        case steady, variable, irregular
    }

    struct Insights: Equatable, Sendable {
        let nightCount: Int
        let averageAsleep: TimeInterval
        /// Time asleep as a share of time asleep plus awake.
        let efficiency: Double
        /// Averaged over staged nights only; nil when none had stages.
        let stageShares: StageShares?
        /// Minutes after midnight, 0..<1440.
        let averageBedtime: Double
        let averageWake: Double
        /// Standard deviation of bedtime and wake time, in minutes.
        let bedtimeSpread: Double
        let wakeSpread: Double
        /// Shortfall against the target over the last `debtWindow` nights.
        let sleepDebt: TimeInterval

        var consistency: Consistency {
            let spread = max(bedtimeSpread, wakeSpread)
            if spread <= SleepInsightsEngine.steadySpread { return .steady }
            if spread <= SleepInsightsEngine.variableSpread { return .variable }
            return .irregular
        }
    }

    /// Fewer nights than this say nothing about regularity.
    static let minNights = 3
    static let windowNights = 14
    static let debtWindow = 7
    static let steadySpread: Double = 30
    static let variableSpread: Double = 60

    static func insights(nights: [SleepScoreEngine.Night], targetHours: Double, calendar: Calendar) -> Insights? {
        let recent = Array(nights.suffix(windowNights))
        guard recent.count >= minNights else { return nil }

        let asleep = recent.map(\.asleep)
        let awake = recent.reduce(0) { $0 + $1.awake }
        let totalAsleep = asleep.reduce(0, +)
        let target = targetHours * 3600

        // Bedtimes straddle midnight, so they are averaged as minutes
        // after noon; wake times rarely do, so midnight is their pivot.
        let bedtimes = recent.map { minutesAfter(pivot: 12 * 60, of: $0.start, calendar: calendar) }
        let wakes = recent.map { minutesAfter(pivot: 0, of: $0.end, calendar: calendar) }

        return Insights(
            nightCount: recent.count,
            averageAsleep: totalAsleep / Double(recent.count),
            efficiency: totalAsleep / (totalAsleep + awake),
            stageShares: stageShares(recent),
            averageBedtime: (mean(bedtimes) + 12 * 60).truncatingRemainder(dividingBy: 24 * 60),
            averageWake: mean(wakes),
            bedtimeSpread: standardDeviation(bedtimes),
            wakeSpread: standardDeviation(wakes),
            sleepDebt: asleep.suffix(debtWindow).reduce(0) { $0 + max(0, target - $1) }
        )
    }

    // MARK: - Private

    private static func stageShares(_ nights: [SleepScoreEngine.Night]) -> StageShares? {
        let staged = nights.filter(\.hasStages)
        guard !staged.isEmpty else { return nil }
        let deep = staged.reduce(0) { $0 + $1.deep }
        let core = staged.reduce(0) { $0 + $1.core }
        let rem = staged.reduce(0) { $0 + $1.rem }
        let total = deep + core + rem
        return StageShares(deep: deep / total, core: core / total, rem: rem / total)
    }

    private static func minutesAfter(pivot: Double, of date: Date, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        return (minutes - pivot + 24 * 60).truncatingRemainder(dividingBy: 24 * 60)
    }

    private static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        let average = mean(values)
        return (values.reduce(0) { $0 + ($1 - average) * ($1 - average) } / Double(values.count)).squareRoot()
    }
}
