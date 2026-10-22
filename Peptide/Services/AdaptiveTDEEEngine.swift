import Foundation

/// Persisted switches for adaptive calorie targets. UserDefaults-backed
/// (device-local) like `HealthSyncSettings`; the targets editor binds the
/// same key through `@AppStorage`.
enum AdaptiveTDEESettings {
    static let enabledKey = "atlas.adaptiveTDEE.enabled.v1"
    /// v2 holds the full accepted targets. The v1 key held calories only;
    /// it is deliberately not read, so upgraded installs stop auto-updating
    /// until the user re-accepts a recommendation rather than risk
    /// overwriting macros edited on another device.
    static let followedTargetsKey = "atlas.adaptiveTDEE.followedTargets.v2"

    /// Defaults to on: an unset key reads as enabled.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Targets the user last accepted from the recommendation. When the
    /// saved targets still equal them in every field, nobody has hand-edited
    /// since (on this device or a synced one), so Atlas may move them as the
    /// adaptive estimate moves. Nil once the user saves custom numbers.
    static var followedTargets: NutritionTargets? {
        get {
            UserDefaults.standard.data(forKey: followedTargetsKey)
                .flatMap { try? JSONDecoder().decode(NutritionTargets.self, from: $0) }
        }
        set {
            let data = newValue.flatMap { try? JSONEncoder().encode($0) }
            UserDefaults.standard.set(data, forKey: followedTargetsKey)
        }
    }
}

/// Estimates daily energy expenditure from what the user actually logged
/// eating and how their weight actually moved over a trailing window —
/// the MacroFactor approach. Energy balance: expenditure = average intake −
/// (weight trend slope × 7 700 kcal/kg).
///
/// The weight trend is the least-squares slope of the window's daily
/// weigh-ins after each reading is clamped against an exponential moving
/// average, so a typo or a salty-dinner water spike can't swing the rate.
/// The slope comes from the clamped readings rather than the EMA itself
/// because an EMA lags a steady loss and would under-read the rate over a
/// four-week window.
///
/// With too little data it returns the formula (Mifflin-St Jeor × activity)
/// estimate; between the minimum and `fullConfidenceDays` it blends the
/// measured value toward the formula.
enum AdaptiveTDEEEngine {

    enum Source: Sendable, Equatable {
        case adaptive
        case formula
    }

    struct Estimate: Sendable, Equatable {
        let kcal: Int
        let source: Source
        /// Logged intake days behind an adaptive estimate; 0 for the formula.
        let intakeDays: Int
        /// Trend rate of weight change in kg/week (negative = losing). Nil
        /// for the formula.
        let weightChangeKgPerWeek: Double?
    }

    /// Trailing window, in days, ending yesterday for intake (today's log is
    /// still partial) and today for weigh-ins.
    static let windowDays = 28
    static let minIntakeDays = 10
    static let minWeightSpanDays = 14
    static let minWeighIns = 3
    /// Intake days / weigh-in span at which the measured value is trusted
    /// outright instead of blended with the formula.
    static let fullConfidenceDays = 21
    static let kcalPerKg: Double = 7_700
    /// Days logged below this are treated as incomplete logs, not fasts.
    static let minLoggedDayKcal = 800
    /// Per-day EMA smoothing factor for the outlier clamp.
    static let trendAlpha: Double = 0.2
    /// Furthest a weigh-in may sit from the running trend before clamping.
    static let maxTrendDeviationKg: Double = 2.5
    /// Fastest believable sustained weight change; caps the implied daily
    /// energy imbalance at ~1 650 kcal.
    static let maxWeeklyChangeKg: Double = 1.5
    static let expenditureBounds: ClosedRange<Double> = 1_200...5_000
    /// Smallest adaptive move worth rewriting the user's saved target for.
    static let minTargetUpdateKcal = 50

    static func estimate(
        weights: [WeightEntry],
        intake: [DailyConsumption],
        formulaTDEE: Double?,
        asOf now: Date,
        calendar: Calendar = .current
    ) -> Estimate? {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: today) else {
            return formulaEstimate(formulaTDEE)
        }

        let loggedKcal = intake
            .filter {
                let day = calendar.startOfDay(for: $0.date)
                return day >= windowStart && day < today && $0.caloriesKcal >= minLoggedDayKcal
            }
            .map(\.caloriesKcal)
        let weighIns = dailyWeighIns(weights, from: windowStart, through: today, calendar: calendar)

        guard
            loggedKcal.count >= minIntakeDays,
            weighIns.count >= minWeighIns,
            let first = weighIns.first, let last = weighIns.last,
            last.day - first.day >= minWeightSpanDays
        else {
            return formulaEstimate(formulaTDEE)
        }

        let maxDailyChange = maxWeeklyChangeKg / 7
        let slope = min(max(slopePerDay(clampingOutliers(weighIns)), -maxDailyChange), maxDailyChange)
        let averageIntake = Double(loggedKcal.reduce(0, +)) / Double(loggedKcal.count)
        let measured = min(max(averageIntake - slope * kcalPerKg, expenditureBounds.lowerBound), expenditureBounds.upperBound)

        let evidenceDays = min(loggedKcal.count, last.day - first.day)
        let confidence = min(1, Double(evidenceDays) / Double(fullConfidenceDays))
        let blended = formulaTDEE.map { confidence * measured + (1 - confidence) * $0 } ?? measured

        return Estimate(
            kcal: Int(blended.rounded()),
            source: .adaptive,
            intakeDays: loggedKcal.count,
            weightChangeKgPerWeek: slope * 7
        )
    }

    /// True when the saved targets are still exactly the ones the user
    /// accepted from the recommendation — every macro, not just calories —
    /// and the new recommendation has moved far enough to be worth applying.
    static func shouldFollow(
        current: NutritionTargets,
        followed: NutritionTargets?,
        next: NutritionTargets
    ) -> Bool {
        followed == current
            && abs(next.calories - current.calories) >= minTargetUpdateKcal
    }

    // MARK: - Internals

    private struct WeighIn {
        /// Whole days since the window start.
        let day: Int
        let kg: Double
    }

    private static func formulaEstimate(_ formulaTDEE: Double?) -> Estimate? {
        formulaTDEE.map {
            Estimate(kcal: Int($0.rounded()), source: .formula, intakeDays: 0, weightChangeKgPerWeek: nil)
        }
    }

    /// One reading per calendar day (the latest that day), oldest first.
    private static func dailyWeighIns(
        _ weights: [WeightEntry],
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) -> [WeighIn] {
        var latestByDay: [Date: WeightEntry] = [:]
        for entry in weights where entry.kg > 0 {
            let day = calendar.startOfDay(for: entry.date)
            guard day >= start, day <= end else { continue }
            if let existing = latestByDay[day], existing.date >= entry.date { continue }
            latestByDay[day] = entry
        }
        return latestByDay
            .map { day, entry in
                WeighIn(day: calendar.dateComponents([.day], from: start, to: day).day ?? 0, kg: entry.kg)
            }
            .sorted { $0.day < $1.day }
    }

    /// Clamps each reading to within `maxTrendDeviationKg` of a time-aware
    /// EMA trend, seeded from the median of the first three readings so a
    /// bad first weigh-in can't anchor the trend.
    private static func clampingOutliers(_ weighIns: [WeighIn]) -> [WeighIn] {
        guard let firstDay = weighIns.first?.day else { return [] }
        var trend = weighIns.prefix(3).map(\.kg).sorted()[min(1, weighIns.count - 1)]
        var previousDay = firstDay
        return weighIns.map { reading in
            let kg = min(max(reading.kg, trend - maxTrendDeviationKg), trend + maxTrendDeviationKg)
            let alpha = 1 - pow(1 - trendAlpha, Double(max(1, reading.day - previousDay)))
            trend += alpha * (kg - trend)
            previousDay = reading.day
            return WeighIn(day: reading.day, kg: kg)
        }
    }

    /// Least-squares slope in kg/day. Gaps are handled naturally because
    /// each reading sits at its real day offset.
    private static func slopePerDay(_ weighIns: [WeighIn]) -> Double {
        let n = Double(weighIns.count)
        let meanDay = weighIns.reduce(0) { $0 + Double($1.day) } / n
        let meanKg = weighIns.reduce(0) { $0 + $1.kg } / n
        var covariance = 0.0
        var variance = 0.0
        for reading in weighIns {
            let dx = Double(reading.day) - meanDay
            covariance += dx * (reading.kg - meanKg)
            variance += dx * dx
        }
        return variance > 0 ? covariance / variance : 0
    }
}
