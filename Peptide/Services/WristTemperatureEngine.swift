import Foundation

/// Last night's sleeping wrist temperature as a deviation from the user's
/// own baseline. Apple Watch records an absolute reading per night, but
/// only the shift matters: a rise of half a degree can mean illness, a
/// late meal or alcohol, and the absolute value differs from wrist to
/// wrist. Pure value-in / value-out so it tests without HealthKit.
enum WristTemperatureEngine {

    struct Reading: Equatable, Sendable {
        /// When the night's sample ended, so it belongs to the wake-up day.
        let date: Date
        let celsius: Double
    }

    struct Deviation: Equatable, Sendable {
        /// Start of the wake-up day of the latest night.
        let night: Date
        /// Signed, in °C: positive is warmer than the baseline.
        let celsius: Double
        /// How many earlier nights the baseline was built from.
        let baselineNights: Int
    }

    /// Apple asks for about five nights before it shows a baseline.
    static let minBaselineNights = 5
    /// Four weeks of nights before the latest one form the baseline.
    static let baselineWindowNights = 28
    /// Days of history to read for a full baseline plus last night.
    static let readDays = baselineWindowNights + 2

    /// The latest night against the median of the nights before it, or
    /// nil when the latest night is older than yesterday's wake-up or the
    /// baseline is too thin to mean anything.
    static func deviation(readings: [Reading], now: Date, calendar: Calendar) -> Deviation? {
        let nights = nightlyAverages(readings, calendar: calendar)
        guard let latest = nights.last, isRecent(latest.day, now: now, calendar: calendar) else { return nil }
        let baseline = nights.dropLast().suffix(baselineWindowNights).map(\.celsius)
        guard baseline.count >= minBaselineNights, let median = median(baseline) else { return nil }
        return Deviation(night: latest.day, celsius: latest.celsius - median, baselineNights: baseline.count)
    }

    /// A deviation in the user's unit: a Fahrenheit *difference* scales by
    /// 1.8 with no offset.
    static func displayDelta(_ celsius: Double, unit: MeasurementUnit) -> Double {
        unit == .imperial ? celsius * 9 / 5 : celsius
    }

    // MARK: - Private

    private struct Night {
        let day: Date
        let celsius: Double
    }

    /// One value per wake-up day, oldest first. A watch can split a night
    /// into several samples; they average into one.
    private static func nightlyAverages(_ readings: [Reading], calendar: Calendar) -> [Night] {
        let byDay = Dictionary(grouping: readings) { calendar.startOfDay(for: $0.date) }
        return byDay
            .map { day, readings in
                Night(day: day, celsius: readings.map(\.celsius).reduce(0, +) / Double(readings.count))
            }
            .sorted { $0.day < $1.day }
    }

    /// Last night's reading belongs to today's wake-up; yesterday's still
    /// counts before this morning's sample has synced.
    private static func isRecent(_ day: Date, now: Date, calendar: Calendar) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return false }
        return day >= yesterday && day <= today
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
