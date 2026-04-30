import Foundation

/// Translates a peptide's published `dosageRange` into a personalized
/// suggestion based on body weight when the literature uses mcg/kg dosing.
///
/// Falls back to the original range when:
///   - the user hasn't entered a weight
///   - the peptide isn't in the weight-scaling table
///   - the dose unit is fixed (mg per injection, IU, etc.)
///
/// Only peptides commonly dosed *daily* in mcg/kg appear in the table.
/// Peptides with weekly / cyclical / loading-phase protocols (TB-500,
/// CJC-1295 DAC, Epitalon) intentionally fall through to their published
/// range so the surrounding UI doesn't paint a misleading "per day" frame.
///
/// The numbers are conservative starting points pulled from common research
/// protocols and are NOT medical advice — surfaced alongside the in-app
/// disclaimer.
enum PeptideDoseCalculator {

    /// mcg/kg/day starting points for peptides commonly dosed daily by body
    /// weight. Keyed by abbreviation (case-sensitive — must match the
    /// canonical database).
    private static let mcgPerKgPerDay: [String: ClosedRange<Double>] = [
        "BPC-157": 2.5...5.0,
        "Tesamorelin": 14.0...28.0,
        "Sermorelin": 1.0...2.0,
        "CJC-1295": 1.0...2.0,
        "Ipamorelin": 1.0...3.0,
        "GHK-Cu": 25.0...50.0,
        "Semax": 4.0...8.0,
        "Selank": 4.0...8.0,
        "AOD-9604": 4.0...6.0,
    ]

    static func dose(for peptide: Peptide, metrics: BodyMetrics) -> String {
        guard let weightKg = metrics.weightKg, weightKg >= 30, weightKg <= 300,
              let range = mcgPerKgPerDay[peptide.abbreviation] else {
            return peptide.dosageRange
        }

        let lower = (range.lowerBound * weightKg).rounded()
        let upper = (range.upperBound * weightKg).rounded()
        return formatMicrograms(lower: lower, upper: upper)
    }

    /// True when this peptide's dose was personalized to the user's weight
    /// (versus falling back to the published research range). Lets the UI
    /// label the difference.
    static func isPersonalized(_ peptide: Peptide, metrics: BodyMetrics) -> Bool {
        guard let weight = metrics.weightKg, weight >= 30, weight <= 300 else {
            return false
        }
        return mcgPerKgPerDay[peptide.abbreviation] != nil
    }

    private static func formatMicrograms(lower: Double, upper: Double) -> String {
        if upper >= 1000 {
            let lowerMg = (lower / 1000 * 100).rounded() / 100
            let upperMg = (upper / 1000 * 100).rounded() / 100
            return "\(trim(lowerMg))–\(trim(upperMg)) mg"
        }
        return "\(Int(lower))–\(Int(upper)) mcg"
    }

    private static func trim(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}
