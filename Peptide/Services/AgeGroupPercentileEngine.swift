import Foundation

/// Places a reading among people of the same sex and age group, from
/// published population tables, so "42 ml/kg/min" becomes "better than
/// 70 % of men your age". Only signals with a large, sex- and
/// age-stratified reference table are covered:
///
/// - **VO2 max**: FRIEND registry, measured treadmill CPX (Kaminsky,
///   Arena & Myers, Mayo Clin Proc 2015;90:1515, Table 3).
/// - **Resting heart rate**: NHANES 1999–2008 (Ostchega et al., National
///   Health Statistics Reports No. 41, 2011, Tables 2 and 3).
///
/// HRV and steps have no comparable table, so they get no placement.
enum AgeGroupPercentileEngine {

    enum Signal: Sendable {
        case vo2Max, restingHeartRate

        /// A lower resting heart rate is the fitter one.
        var higherIsBetter: Bool { self == .vo2Max }
    }

    /// The percentiles every row lists values for.
    static let percentiles: [Double] = [5, 10, 25, 50, 75, 90, 95]

    /// Share of the age group, 5…95, whose reading this one beats, or nil
    /// when the sex has no table.
    static func betterThan(_ signal: Signal, value: Double, age: Int, sex: BiologicalSex) -> Int? {
        guard let row = row(for: signal, age: age, sex: sex) else { return nil }
        let percentile = interpolate(value, in: row)
        let share = signal.higherIsBetter ? percentile : 100 - percentile
        return Int(share.rounded())
    }

    // MARK: - Tables

    /// Lower age bound of each row, with the row's values at `percentiles`.
    private typealias Table = [(minAge: Int, values: [Double])]

    private static let vo2Male: Table = [
        (20, [29.0, 32.1, 40.1, 48.0, 55.2, 61.8, 66.3]),
        (30, [27.2, 30.2, 35.9, 42.4, 49.2, 56.5, 59.8]),
        (40, [24.2, 26.8, 31.9, 37.8, 45.0, 52.1, 55.6]),
        (50, [20.9, 22.8, 27.1, 32.6, 39.7, 45.6, 50.7]),
        (60, [17.4, 19.8, 23.7, 28.2, 34.5, 40.3, 43.0]),
        (70, [16.3, 17.1, 20.4, 24.4, 30.4, 36.6, 39.7]),
    ]

    private static let vo2Female: Table = [
        (20, [21.7, 23.9, 30.5, 37.6, 44.7, 51.3, 56.0]),
        (30, [19.0, 20.9, 25.3, 30.2, 36.1, 41.4, 45.8]),
        (40, [17.0, 18.8, 22.1, 26.7, 32.4, 38.4, 41.7]),
        (50, [16.0, 17.3, 19.9, 23.4, 27.6, 32.0, 35.9]),
        (60, [13.4, 14.6, 17.2, 20.0, 23.8, 27.0, 29.4]),
        (70, [13.1, 13.6, 15.6, 18.3, 20.8, 23.1, 24.1]),
    ]

    private static let rhrMale: Table = [
        (20, [52, 55, 61, 69, 76, 84, 89]),
        (40, [52, 55, 61, 68, 77, 85, 90]),
        (60, [50, 54, 60, 67, 75, 84, 91]),
        (80, [51, 54, 61, 68, 78, 86, 94]),
    ]

    private static let rhrFemale: Table = [
        (20, [57, 60, 66, 74, 82, 89, 95]),
        (40, [56, 59, 64, 71, 79, 86, 92]),
        (60, [56, 59, 64, 70, 78, 86, 92]),
        (80, [56, 59, 64, 71, 77, 85, 93]),
    ]

    // MARK: - Private

    /// Ages outside the table use its nearest row.
    private static func row(for signal: Signal, age: Int, sex: BiologicalSex) -> [Double]? {
        let table: Table
        switch (signal, sex) {
        case (.vo2Max, .male): table = vo2Male
        case (.vo2Max, .female): table = vo2Female
        case (.restingHeartRate, .male): table = rhrMale
        case (.restingHeartRate, .female): table = rhrFemale
        default: return nil
        }
        return (table.last { age >= $0.minAge } ?? table.first)?.values
    }

    /// Linear between the listed percentiles, clamped to 5…95: the tables
    /// say nothing about the tails.
    private static func interpolate(_ value: Double, in values: [Double]) -> Double {
        guard let first = values.first, let last = values.last else { return 50 }
        if value <= first { return percentiles[0] }
        if value >= last { return percentiles[percentiles.count - 1] }
        for index in 1..<values.count where value <= values[index] {
            let low = values[index - 1], high = values[index]
            let fraction = high > low ? (value - low) / (high - low) : 0
            return percentiles[index - 1] + fraction * (percentiles[index] - percentiles[index - 1])
        }
        return percentiles[percentiles.count - 1]
    }
}
