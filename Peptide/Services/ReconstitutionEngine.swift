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

    /// A U-100 insulin syringe holds 1 mL, i.e. 100 units.
    static let syringeCapacityUnits: Double = 100

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
    /// Divides in micrograms and floors with a small tolerance: 7 mg ÷
    /// 0.14 mg lands at 49.999…, which would otherwise read one short.
    static func amountsPerVial(amountMcg: Double, vialMg: Double) -> Int? {
        guard isPositive(amountMcg), isPositive(vialMg) else { return nil }
        let count = (micrograms(fromMilligrams: vialMg) / amountMcg + 1e-9).rounded(.down)
        return countable(count)
    }

    static func roundedUnits(_ units: Double) -> Int? {
        countable(units.rounded())
    }

    /// Below this, a draw is shown to the tenth of a unit.
    static let smallDrawUnits: Double = 10

    /// Units as shown: whole units, or tenths below `smallDrawUnits` so a
    /// real 0.2-unit draw never reads as 0. A positive draw shows at
    /// least 0.1.
    static func displayUnits(_ units: Double) -> Double? {
        guard units > 0, units < smallDrawUnits else { return roundedUnits(units).map(Double.init) }
        return max(0.1, (units * 10).rounded() / 10)
    }

    /// `displayUnits` as text, prefixed "≈ " when it isn't the exact
    /// amount, so 12.6 reads "≈ 13" rather than silently "13".
    static func unitsLabel(_ units: Double, approximate: Bool = true) -> String? {
        guard let shown = displayUnits(units) else { return nil }
        let text = shown.formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
        return approximate && abs(units - shown) > fractionalTolerance ? "≈ \(text)" : text
    }

    /// True when the result needs more than one full U-100 syringe.
    static func exceedsSyringe(units: Double) -> Bool {
        units.isFinite && units > syringeCapacityUnits
    }

    /// Parses a typed amount. Trims the ends and accepts a comma
    /// decimal separator, but rejects interior junk ("2 50") rather
    /// than guessing, and rejects zero, negatives and empty input.
    /// A value that could be digit grouping ("1,000", "1.000,5") is
    /// rejected too: reading it as a decimal would be a 1000x error.
    static func parseAmount(_ text: String) -> Double? {
        guard !hasAmbiguousSeparator(text) else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), isPositive(value) else { return nil }
        return value
    }

    /// More than one separator, or a single one followed by exactly
    /// three digits after a non-zero whole part, reads as grouping in
    /// some locales and as a decimal in others. The calculator uses it
    /// to explain why such input gives no result.
    static func hasAmbiguousSeparator(_ text: String) -> Bool {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ",", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: ".", omittingEmptySubsequences: false) }
        guard parts.count > 1 else { return false }
        guard parts.count == 2 else { return true }
        let whole = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        let wholeIsZero = !whole.isEmpty && whole.allSatisfy { $0 == "0" }
        return parts[1].count == 3 && !whole.isEmpty && !wholeIsZero
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
