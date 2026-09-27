import Foundation

/// Pure unit conversions behind the reconstitution calculator: a vial
/// of powder (mg) dissolved in water (mL) gives a concentration
/// (mg/mL); an amount (mcg) at that concentration occupies a volume
/// that reads as units on a U-100 syringe (100 units = 1 mL).
///
/// Every function returns nil rather than 0, infinity or NaN when an
/// input is zero, negative or non-finite, so callers render a
/// placeholder instead of a nonsense number.
enum ReconstitutionEngine {

    /// Units on a U-100 syringe per millilitre.
    static let unitsPerMilliliter: Double = 100

    static let microgramsPerMilligram: Double = 1000

    /// Rounded results beyond this can't be shown and would trap on
    /// conversion to `Int`.
    private static let largestCountableValue: Double = 1e12

    /// A result further than this from its rounded integer is shown
    /// as approximate ("≈ 13") rather than exact.
    private static let fractionalTolerance: Double = 0.05

    static func milligrams(fromMicrograms micrograms: Double) -> Double {
        micrograms / microgramsPerMilligram
    }

    static func micrograms(fromMilligrams milligrams: Double) -> Double {
        milligrams * microgramsPerMilligram
    }

    static func concentrationMgPerMl(vialMg: Double, waterMl: Double) -> Double? {
        guard isPositive(vialMg), isPositive(waterMl) else { return nil }
        return finite(vialMg / waterMl)
    }

    /// `units = (amountMg / concentrationMgPerMl) × 100`.
    static func syringeUnits(amountMcg: Double, vialMg: Double, waterMl: Double) -> Double? {
        guard
            isPositive(amountMcg),
            let concentration = concentrationMgPerMl(vialMg: vialMg, waterMl: waterMl)
        else { return nil }
        let volumeMl = milligrams(fromMicrograms: amountMcg) / concentration
        return finite(volumeMl * unitsPerMilliliter)
    }

    /// Whole amounts of `amountMcg` a vial of `vialMg` holds, rounded down.
    static func amountsPerVial(amountMcg: Double, vialMg: Double) -> Int? {
        guard isPositive(amountMcg), isPositive(vialMg) else { return nil }
        let count = (vialMg / milligrams(fromMicrograms: amountMcg)).rounded(.down)
        return countable(count)
    }

    static func roundedUnits(_ units: Double) -> Int? {
        countable(units.rounded())
    }

    static func hasFractionalUnits(_ units: Double) -> Bool {
        guard let rounded = roundedUnits(units) else { return false }
        return abs(units - Double(rounded)) > fractionalTolerance
    }

    /// Parses a typed amount. Trims the ends and accepts a comma
    /// decimal separator, but rejects interior junk ("2 50") rather
    /// than guessing, and rejects zero, negatives and empty input.
    static func parseAmount(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), isPositive(value) else { return nil }
        return value
    }

    private static func isPositive(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }

    private static func finite(_ value: Double) -> Double? {
        value.isFinite ? value : nil
    }

    private static func countable(_ value: Double) -> Int? {
        guard value.isFinite, abs(value) <= largestCountableValue else { return nil }
        return Int(value)
    }
}
