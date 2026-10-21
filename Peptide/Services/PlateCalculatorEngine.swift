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

    /// Unlimited supply of each size. When the target isn't loadable it
    /// settles on the nearer of the heaviest load under it and the lightest
    /// load over it, preferring the lighter on a tie — so 22 kg on a 20 kg
    /// bar becomes 22.5, but 21 stays the empty bar. Searches every
    /// reachable load rather than filling greedily, so an odd plate set
    /// (only 25s and 20s) still finds 20 + 20 for 40 a side.
    static func calculate(target: Double, barWeight: Double, plates: [Double]) -> Outcome {
        guard isPlausible(target), barWeight == 0 || isPlausible(barWeight) else { return .invalid }
        let targetUnits = hundredths(target)
        let barUnits = hundredths(barWeight)
        guard targetUnits >= barUnits else { return .belowBar }

        let sizes = usablePlates(plates)
        let perSide = nearestLoad(
            perSideUnits: (targetUnits - barUnits) / 2,
            sizes: sizes,
            isCloserOver: { under, over in
                barUnits + 2 * over - targetUnits < targetUnits - (barUnits + 2 * under)
            }
        )

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

    /// The heaviest one-side load at or under `perSideUnits`, or the lightest
    /// one over it when `isCloserOver(under, over)` says so. Works in steps
    /// of the plates' common divisor so a full kilo rack stays a few hundred
    /// cells, and every load in range is checked, not just the greedy one.
    private static func nearestLoad(
        perSideUnits: Int,
        sizes: [Int],
        isCloserOver: (_ under: Int, _ over: Int) -> Bool
    ) -> [UnitCount] {
        guard let lightest = sizes.last else { return [] }
        let step = sizes.reduce(0, gcd)
        let steps = sizes.map { $0 / step }
        let floorStep = perSideUnits / step
        // The best load under plus one lightest plate is always over the
        // target, so nothing past here can be the nearest load over it.
        let reachable = reachableSteps(upTo: floorStep + lightest / step, sizes: steps)

        let under = (0...floorStep).last { reachable[$0] } ?? 0
        let over = ((floorStep + 1)...(under + lightest / step)).first { reachable[$0] }
        let chosen = over.flatMap { isCloserOver(under * step, $0 * step) ? $0 : nil } ?? under
        return stack(forSteps: chosen, sizes: steps, reachable: reachable)
            .map { UnitCount(size: $0.size * step, count: $0.count) }
    }

    /// `reachable[n]` is true when some mix of plates sums to exactly n steps.
    private static func reachableSteps(upTo limit: Int, sizes: [Int]) -> [Bool] {
        var reachable = [Bool](repeating: false, count: limit + 1)
        reachable[0] = true
        for amount in stride(from: 1, through: limit, by: 1) {
            reachable[amount] = sizes.contains { $0 <= amount && reachable[amount - $0] }
        }
        return reachable
    }

    /// Rebuilds a reachable load heaviest plate first, taking the heaviest
    /// plate that still leaves a reachable rest.
    private static func stack(forSteps total: Int, sizes: [Int], reachable: [Bool]) -> [UnitCount] {
        var remaining = total
        var stack: [UnitCount] = []
        while remaining > 0, let size = sizes.first(where: { $0 <= remaining && reachable[remaining - $0] }) {
            if let last = stack.last, last.size == size {
                stack[stack.count - 1] = UnitCount(size: size, count: last.count + 1)
            } else {
                stack.append(UnitCount(size: size, count: 1))
            }
            remaining -= size
        }
        return stack
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
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
