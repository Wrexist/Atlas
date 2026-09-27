import Foundation

/// Works out which plates go on each side of a barbell to reach a target
/// total. Pure and unit-agnostic: every weight in and out is in the same
/// display unit (kg or lb), and `MeasurementUnit` only picks the defaults.
///
/// Arithmetic runs in integer hundredths so 1.25 kg change plates add up
/// exactly instead of drifting through binary floating point.
enum PlateCalculatorEngine {

    struct PlateCount: Equatable, Sendable {
        let weight: Double
        let count: Int
    }

    struct Loadout: Equatable, Sendable {
        /// Plates for ONE side, heaviest first. The other side mirrors it.
        let perSide: [PlateCount]
        /// Bar plus both sides — what is actually on the bar.
        let loadedTotal: Double
        /// Target minus `loadedTotal`: the part the available plates
        /// cannot make. Zero when the target is exactly loadable.
        let remainder: Double

        var isExact: Bool { remainder == 0 }

        /// One entry per physical plate on a side, heaviest first — the
        /// order they slide onto the sleeve.
        var platesPerSide: [Double] {
            perSide.flatMap { Array(repeating: $0.weight, count: $0.count) }
        }
    }

    enum Outcome: Equatable, Sendable {
        case loaded(Loadout)
        /// The target is lighter than the empty bar.
        case belowBar
        /// A non-finite, non-positive or absurdly large target or bar weight.
        case invalid
    }

    /// Ceiling on any weight fed in. Far above anything a bar holds, and
    /// low enough that the fixed-point conversion can never overflow `Int`.
    static let maximumWeight: Double = 10_000

    static let kilogramPlates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    static let poundPlates: [Double] = [45, 35, 25, 10, 5, 2.5]

    static func defaultBarWeight(for unit: MeasurementUnit) -> Double {
        unit == .metric ? 20 : 45
    }

    static func defaultPlates(for unit: MeasurementUnit) -> [Double] {
        unit == .metric ? kilogramPlates : poundPlates
    }

    /// Greedy, heaviest plate first, with an unlimited supply of each
    /// size. For the standard plate sets greedy is optimal; for an odd
    /// custom set it still never overshoots the target.
    static func calculate(target: Double, barWeight: Double, plates: [Double]) -> Outcome {
        guard isPlausible(target), isPlausible(barWeight) else { return .invalid }
        let targetUnits = hundredths(target)
        let barUnits = hundredths(barWeight)
        guard targetUnits >= barUnits else { return .belowBar }

        var remainingPerSide = (targetUnits - barUnits) / 2
        var perSide: [PlateCount] = []
        for plate in usablePlates(plates) {
            let count = remainingPerSide / plate
            guard count > 0 else { continue }
            perSide.append(PlateCount(weight: value(plate), count: count))
            remainingPerSide -= count * plate
        }

        let loadedUnits = barUnits + 2 * perSide.reduce(0) { $0 + hundredths($1.weight) * $1.count }
        return .loaded(Loadout(
            perSide: perSide,
            loadedTotal: value(loadedUnits),
            remainder: value(targetUnits - loadedUnits)
        ))
    }

    // MARK: - Fixed-point helpers

    /// Positive, de-duplicated plate sizes in hundredths, heaviest first.
    private static func usablePlates(_ plates: [Double]) -> [Int] {
        Array(Set(plates.filter(isPlausible).map(hundredths)))
            .filter { $0 > 0 }
            .sorted(by: >)
    }

    private static func isPlausible(_ weight: Double) -> Bool {
        weight.isFinite && weight > 0 && weight <= maximumWeight
    }

    private static func hundredths(_ weight: Double) -> Int {
        Int((weight * 100).rounded())
    }

    private static func value(_ hundredths: Int) -> Double {
        Double(hundredths) / 100
    }
}
