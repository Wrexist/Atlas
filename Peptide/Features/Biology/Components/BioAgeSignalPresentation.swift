import SwiftUI

/// How each Biological Age signal is named, drawn and explained. One switch
/// per question so the hero, the drivers card, the coverage card and the
/// explainer all say the same thing about the same signal.
extension PerformanceAgeEngine.Driver.Kind {

    var displayName: String {
        switch self {
        case .vo2Max:        String(localized: "Cardio fitness")
        case .hrv:           String(localized: "HRV")
        case .rhr:           String(localized: "Resting heart rate")
        case .sleep:         String(localized: "Sleep")
        case .steps:         String(localized: "Daily steps")
        case .bodyMassIndex: String(localized: "BMI")
        case .weight:        String(localized: "Weight trend")
        case .hba1c:         String(localized: "HbA1c")
        case .ldl:           String(localized: "LDL cholesterol")
        case .crp:           String(localized: "Inflammation (hs-CRP)")
        }
    }

    var icon: String {
        switch self {
        case .vo2Max:        "lungs.fill"
        case .hrv:           "waveform.path.ecg"
        case .rhr:           "heart.fill"
        case .sleep:         "bed.double.fill"
        case .steps:         "figure.walk"
        case .bodyMassIndex: "figure"
        case .weight:        "scalemass.fill"
        case .hba1c:         "drop.fill"
        case .ldl:           "heart.circle.fill"
        case .crp:           "flame.fill"
        }
    }

    /// The metric palette where one exists, so a signal wears the same
    /// colour here as on the rest of the app's health surfaces.
    var tint: Color {
        switch self {
        case .vo2Max, .steps:        AppColor.metricActivity
        case .hrv:                   AppColor.metricHRV
        case .rhr:                   AppColor.metricHeartRate
        case .sleep:                 AppColor.metricSleep
        case .bodyMassIndex, .weight: AppColor.accentLight
        case .hba1c:                 AppColor.labMetabolic
        case .ldl:                   AppColor.labLipids
        case .crp:                   AppColor.labOrganHealth
        }
    }

    /// What the signal measures and why it moves the estimate. Used by the
    /// explainer sheet.
    var explanation: String {
        switch self {
        case .vo2Max:
            String(localized: "Apple Health's VO2 max estimate, compared with what's typical for your age and sex. Higher cardio fitness reads younger.")
        case .hrv:
            String(localized: "Your 30-day median, compared with what's typical for your age. Higher variability reads as a better-recovered nervous system.")
        case .rhr:
            String(localized: "Your 30-day median. A lower resting rate tracks with aerobic fitness.")
        case .sleep:
            String(localized: "Median hours asleep per night. Short sleep adds years; past 7.5 hours it stops counting either way.")
        case .steps:
            String(localized: "Your 30-day median. More daily movement reads younger, up to about 10,000 steps.")
        case .bodyMassIndex:
            String(localized: "From the height and weight in your profile. It only ever adds a little, because BMI can't tell muscle from fat.")
        case .weight:
            String(localized: "How fast your weight moved over 30 days, not the number itself. A rapid change in either direction adds a little.")
        case .hba1c:
            String(localized: "Your latest HbA1c from Labs, if drawn in the past year. It reflects average blood sugar over about three months; lower reads younger, and 6.5% or more adds the most.")
        case .ldl:
            String(localized: "Your latest LDL cholesterol from Labs, if drawn in the past year. Lower reads younger; 190 mg/dL or more adds the most.")
        case .crp:
            String(localized: "Your latest hs-CRP from Labs, if drawn in the past year. Under 1 mg/L reads younger; over 3 mg/L adds the most. A cold or a hard workout can raise it for a few days.")
        }
    }

    /// The single next step that would let this signal count.
    var guidance: String {
        switch self {
        case .vo2Max:
            String(localized: "Wear Apple Watch on an outdoor walk, run or hike to get a cardio fitness reading.")
        case .hrv:
            String(localized: "Wear Apple Watch, including overnight, to record HRV.")
        case .rhr:
            String(localized: "Wear Apple Watch through the day to record resting heart rate.")
        case .sleep:
            String(localized: "Track sleep with Apple Watch or an app that writes sleep to Apple Health.")
        case .steps:
            String(localized: "Carry your iPhone or wear Apple Watch to count steps.")
        case .bodyMassIndex:
            String(localized: "Add your height and weight in your profile.")
        case .weight:
            String(localized: "Log your weight at least twice a month.")
        case .hba1c, .ldl, .crp:
            String(localized: "Add a result from the past year in Labs.")
        }
    }

    /// True when the data comes from Apple Health rather than the profile
    /// or the in-app weight log.
    var comesFromHealth: Bool {
        switch self {
        case .vo2Max, .hrv, .rhr, .sleep, .steps: true
        case .bodyMassIndex, .weight,
             .hba1c, .ldl, .crp:                  false
        }
    }

    /// "48 ms", "8,412 steps", "+1.2 kg" — the user's reading.
    func formattedValue(_ value: Double, unit: MeasurementUnit) -> String {
        switch self {
        case .vo2Max:        String(localized: "\(value.formatted(.number.precision(.fractionLength(1)))) ml/kg/min")
        case .hrv:           String(localized: "\(Int(value.rounded())) ms")
        case .rhr:           String(localized: "\(Int(value.rounded())) bpm")
        case .sleep:         String(localized: "\(value.formatted(.number.precision(.fractionLength(1)))) h")
        case .steps:         String(localized: "\(value.formatted(.number.precision(.fractionLength(0)))) steps")
        case .bodyMassIndex: value.formatted(.number.precision(.fractionLength(1)))
        case .weight:        signedWeight(value, unit: unit)
        case .hba1c:         String(localized: "\(value.formatted(.number.precision(.fractionLength(1)))) %")
        case .ldl:           String(localized: "\(Int(value.rounded())) mg/dL")
        case .crp:           String(localized: "\(value.formatted(.number.precision(.fractionLength(1)))) mg/L")
        }
    }

    /// The reading the signal is measured against, phrased per signal.
    func formattedReference(_ reference: Double, unit: MeasurementUnit) -> String {
        switch self {
        case .vo2Max:
            String(localized: "Typical for your age: \(reference.formatted(.number.precision(.fractionLength(1)))) ml/kg/min")
        case .hrv:
            String(localized: "Typical for your age: \(Int(reference.rounded())) ms")
        case .rhr:
            String(localized: "Neutral at \(Int(reference.rounded())) bpm")
        case .sleep:
            String(localized: "Target: \(reference.formatted(.number.precision(.fractionLength(1)))) h")
        case .steps:
            String(localized: "Neutral at \(reference.formatted(.number.precision(.fractionLength(0)))) steps")
        case .bodyMassIndex:
            String(localized: "Neutral up to \(reference.formatted(.number.precision(.fractionLength(0))))")
        case .weight:
            String(localized: "Neutral within ±\(magnitude(reference, unit: unit))")
        case .hba1c:
            String(localized: "Neutral at \(reference.formatted(.number.precision(.fractionLength(1)))) %")
        case .ldl:
            String(localized: "Neutral at \(Int(reference.rounded())) mg/dL")
        case .crp:
            String(localized: "Neutral at \(reference.formatted(.number.precision(.fractionLength(1)))) mg/L")
        }
    }

    private func signedWeight(_ kg: Double, unit: MeasurementUnit) -> String {
        let sign = kg > 0 ? "+" : (kg < 0 ? "−" : "")
        return sign + magnitude(abs(kg), unit: unit)
    }

    private func magnitude(_ kg: Double, unit: MeasurementUnit) -> String {
        "\(unit.weightValue(kg, fractionDigits: 1...1)) \(unit.weightSuffix)"
    }
}

enum BioAgeFormat {
    /// "−1.2 yr" / "+0.4 yr" for a signed contribution in years, with the
    /// locale's decimal separator.
    static func years(_ delta: Double) -> String {
        let rounded = (delta * 10).rounded() / 10
        let sign = rounded > 0 ? "+" : (rounded < 0 ? "−" : "")
        return String(localized: "\(sign)\(age(abs(rounded))) yr")
    }

    /// Spoken form for VoiceOver: "1.2 years younger".
    static func spokenYears(_ delta: Double) -> String {
        let magnitude = age(abs(delta))
        if abs(delta) < 0.05 { return String(localized: "No effect") }
        return delta < 0
            ? String(localized: "\(magnitude) years younger")
            : String(localized: "\(magnitude) years older")
    }

    /// "33.4", with the locale's decimal separator.
    static func age(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
