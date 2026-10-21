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
        /// Target minus `loadedTotal`. Zero when the target is exactly
        /// loadable; negative when the nearest load is just over it.
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
        /// A non-finite, non-positive or absurdly large target, or a
        /// negative or absurd bar weight. A bar may weigh zero: some Smith
        /// machines are counterbalanced.
        case invalid
    }

    /// Ceiling on any weight fed in. Far above anything a bar holds, and
    /// low enough that the fixed-point conversion can never overflow `Int`.
    static let maximumWeight: Double = 10_000

    static let kilogramPlates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    static let poundPlates: [Double] = [45, 35, 25, 10, 5, 2.5]

    static func defaultPlates(for unit: MeasurementUnit) -> [Double] {
        unit == .metric ? kilogramPlates : poundPlates
    }

    /// Greedy, heaviest plate first, with an unlimited supply of each
    /// size. When the target isn't loadable it settles on the nearer of
    /// the best load under it and that load plus one lightest plate a
    /// side, preferring the lighter on a tie — so 22 kg on a 20 kg bar
    /// becomes 22.5, but 21 stays the empty bar.
    static func calculate(target: Double, barWeight: Double, plates: [Double]) -> Outcome {
        guard isPlausible(target), barWeight == 0 || isPlausible(barWeight) else { return .invalid }
        let targetUnits = hundredths(target)
        let barUnits = hundredths(barWeight)
        guard targetUnits >= barUnits else { return .belowBar }

        let sizes = usablePlates(plates)
        var perSide = load(perSideUnits: (targetUnits - barUnits) / 2, sizes: sizes)
        if let lightest = sizes.last {
            let under = barUnits + 2 * units(perSide)
            let heavier = load(perSideUnits: units(perSide) + lightest, sizes: sizes)
            let over = barUnits + 2 * units(heavier)
            if over > targetUnits, over - targetUnits < targetUnits - under { perSide = heavier }
        }

        let loadedUnits = barUnits + 2 * units(perSide)
        return .loaded(Loadout(
            perSide: perSide.map { PlateCount(weight: value($0.size), count: $0.count) },
            loadedTotal: value(loadedUnits),
            remainder: value(targetUnits - loadedUnits)
        ))
    }

    /// The smallest change in total load the plates allow — one of the
    /// lightest plate on each side. Nil when there are no usable plates.
    static func smallestJump(plates: [Double]) -> Double? {
        usablePlates(plates).last.map { value(2 * $0) }
    }

    // MARK: - Plate colours

    /// Competition colour bands, by a plate's weight in kilos so pound
    /// plates take the colour of their nearest kilo cousin (45 lb is
    /// blue like 20 kg). Change plates below 5 kg are all grey.
    enum Tone: Equatable, Sendable {
        case red, blue, yellow, green, white, grey
    }

    static func tone(forPlate weight: Double, unit: MeasurementUnit) -> Tone {
        switch unit.kilograms(fromDisplayed: weight) {
        case 22.5...:     return .red
        case 17.5..<22.5: return .blue
        case 12.5..<17.5: return .yellow
        case 7.5..<12.5:  return .green
        case 4.5..<7.5:   return .white
        default:          return .grey
        }
    }

    // MARK: - Fixed-point helpers

    private struct UnitCount {
        let size: Int
        let count: Int
    }

    /// Greedy fill of one side, never over `perSideUnits`.
    private static func load(perSideUnits: Int, sizes: [Int]) -> [UnitCount] {
        var remaining = perSideUnits
        var stack: [UnitCount] = []
        for size in sizes {
            let count = remaining / size
            guard count > 0 else { continue }
            stack.append(UnitCount(size: size, count: count))
            remaining -= count * size
        }
        return stack
    }

    private static func units(_ stack: [UnitCount]) -> Int {
        stack.reduce(0) { $0 + $1.size * $1.count }
    }

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
