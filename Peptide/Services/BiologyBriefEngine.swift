import Foundation

/// The Biology summary Ask Atlas attaches, with the user's consent: the
/// estimate, its trend, and each signal's reading, reference and pull.
/// Signals are worded with the same presentation the drivers card uses,
/// so the model reads what the user sees, in the user's language and units.
enum BiologyBriefEngine {

    static func brief(_ resolved: BioAgeStateResolver.Resolved, unit: MeasurementUnit) -> String {
        var lines = [headline(resolved)]
        if let trend = trendLine(resolved.trend) {
            lines.append(trend)
        }
        let drivers = signals(resolved)
        if !drivers.isEmpty {
            lines.append("Signals (30-day readings; years each adds + or removes −):")
            lines += drivers.map { "- " + driverLine($0, unit: unit) }
        }
        let present = Set(drivers.map(\.kind))
        let missing = PerformanceAgeEngine.Driver.Kind.allCases.filter { !present.contains($0) }
        if !missing.isEmpty {
            lines.append("Not available: " + missing.map(\.displayName).joined(separator: ", ") + ".")
        }
        return lines.joined(separator: "\n")
    }

    private static func headline(_ resolved: BioAgeStateResolver.Resolved) -> String {
        let age = resolved.chronologicalAge
        switch resolved.state {
        case .unlocked(let estimate):
            let confidence = Int((estimate.confidence * 100).rounded())
            return "Biological Age: \(BioAgeFormat.age(estimate.biologicalAge)), chronological age \(age), confidence \(confidence)%."
        case .building(let days, _):
            return "No Biological Age yet: \(days) of \(PerformanceAgeEngine.windowDays) days of heart and sleep data so far. Chronological age \(age)."
        case .locked, .needsAge:
            return "No Biological Age available."
        }
    }

    /// Oldest and newest weekly points, so "how has it moved" has an answer.
    private static func trendLine(_ trend: [PerformanceAgeEngine.TrendPoint]) -> String? {
        guard trend.count > 1, let first = trend.first, let last = trend.last else { return nil }
        return "Trend: \(BioAgeFormat.age(first.biologicalAge)) on \(first.date.formatted(dayFormat)), "
            + "\(BioAgeFormat.age(last.biologicalAge)) on \(last.date.formatted(dayFormat))."
    }

    /// yyyy-MM-dd in the user's zone: points sit at local midnight, which
    /// the default GMT style would print as the day before east of UTC.
    private static var dayFormat: Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
    }

    /// The estimate's drivers once unlocked; while building, the same
    /// signals scored from the inputs, so the chat can still say what's
    /// there and what's missing.
    private static func signals(_ resolved: BioAgeStateResolver.Resolved) -> [PerformanceAgeEngine.Driver] {
        if case .unlocked(let estimate) = resolved.state { return estimate.drivers }
        return resolved.inputs.map(PerformanceAgeEngine.drivers(for:)) ?? []
    }

    private static func driverLine(_ driver: PerformanceAgeEngine.Driver, unit: MeasurementUnit) -> String {
        var line = driver.kind.displayName
        if let value = driver.value {
            line += ": " + driver.kind.formattedValue(value, unit: unit)
        }
        if let reference = driver.reference {
            line += " (" + driver.kind.formattedReference(reference, unit: unit) + ")"
        }
        return line + " → " + BioAgeFormat.years(driver.deltaYears)
    }
}
