import Foundation

/// Turns what the user types for a manual body measurement into a
/// canonical metric value (% / cm / mmHg / °C), or nil when it is not a
/// reading a person can plausibly take. The ranges are wide on purpose:
/// they catch a slipped digit, not an unusual body.
enum BodyMeasurementInput {
    static let bodyFatPercent: ClosedRange<Double> = 2...70
    static let waistCentimeters: ClosedRange<Double> = 40...200
    static let systolic: ClosedRange<Double> = 70...250
    static let diastolic: ClosedRange<Double> = 40...150
    static let bodyTemperatureCelsius: ClosedRange<Double> = 34...42

    /// Metric range for a single-value biomarker; for blood pressure,
    /// the systolic range. Nil for biomarkers the user doesn't type.
    static func plausibleRange(for biomarker: Biomarker) -> ClosedRange<Double>? {
        switch biomarker {
        case .bodyFat:          bodyFatPercent
        case .waist:            waistCentimeters
        case .bloodPressure:    systolic
        case .bodyTemperature:  bodyTemperatureCelsius
        default:                nil
        }
    }

    /// "18,5" and "18.5" both read as 18.5, so a Swedish decimal pad works.
    static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// A typed value in the user's display unit, converted to metric and
    /// range-checked.
    static func metricValue(_ text: String, for biomarker: Biomarker, unit: MeasurementUnit) -> Double? {
        guard let typed = number(text), let range = plausibleRange(for: biomarker) else { return nil }
        let metric: Double
        switch (biomarker, unit) {
        case (.waist, .imperial):           metric = typed * 2.54
        case (.bodyTemperature, .imperial): metric = (typed - 32) * 5 / 9
        default:                            metric = typed
        }
        return range.contains(metric) ? metric : nil
    }

    /// Both numbers in range, systolic the higher of the two.
    static func bloodPressure(systolic systolicText: String, diastolic diastolicText: String) -> (systolic: Double, diastolic: Double)? {
        guard let high = number(systolicText), let low = number(diastolicText),
              systolic.contains(high), diastolic.contains(low), high > low
        else { return nil }
        return (high, low)
    }
}
