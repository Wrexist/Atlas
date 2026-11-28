import Foundation

/// The arithmetic behind the set picker's wheels. Weight turns as two
/// wheels, whole units and a fraction, like Health's weight entry, so a
/// big jump is one flick while any loadable weight stays reachable. The
/// step buttons move by the equipment's smallest jump and land on that
/// step's grid, so a bar at 81 kg goes to 82.5, not 83.5.
enum SetValueWheelEngine {
    struct Weight: Equatable {
        var whole: Int
        var fraction: Double

        var value: Double { Double(whole) + fraction }
    }

    /// Quarter kilograms cover 1.25 kg plates and micro-plates; half
    /// pounds cover 2.5 lb plates.
    static func fractions(for unit: MeasurementUnit) -> [Double] {
        unit == .metric ? [0, 0.25, 0.5, 0.75] : [0, 0.5]
    }

    /// The wheel's top: 500 kg or 1 100 lb, or higher when the set
    /// already holds more.
    static func wholeRange(for unit: MeasurementUnit, holding displayValue: Double) -> ClosedRange<Int> {
        let ceiling = unit == .metric ? 500 : 1100
        let upper = min(Int(unit.weightForDisplay(SetEntryLimits.weightKg.upperBound)), max(ceiling, Int(displayValue.rounded(.up))))
        return 0...upper
    }

    static func repsRange(holding reps: Int) -> ClosedRange<Int> {
        0...min(SetEntryLimits.reps.upperBound, max(100, reps))
    }

    /// The nearest point on the wheels, carrying into the next whole
    /// unit when the fraction rounds up past the last one.
    static func split(_ displayValue: Double, unit: MeasurementUnit) -> Weight {
        let value = max(0, displayValue)
        let fractions = fractions(for: unit)
        let grain = fractions[1]
        let snapped = (value / grain).rounded() * grain
        let whole = snapped.rounded(.down)
        let remainder = snapped - whole
        let fraction = fractions.min { abs($0 - remainder) < abs($1 - remainder) } ?? 0
        return Weight(whole: Int(whole), fraction: fraction)
    }

    /// The step the plus and minus buttons take, in the display unit.
    /// Equipment without a comparable step (bands, bodyweight) moves by
    /// one kilogram or 2.5 lb.
    static func displayStep(incrementKg: Double?, unit: MeasurementUnit) -> Double {
        guard let incrementKg, incrementKg > 0 else { return unit == .metric ? 1 : 2.5 }
        return (unit.weightForDisplay(incrementKg) * 100).rounded() / 100
    }

    /// One step up or down, snapped onto the step's grid. Off-grid values
    /// move to the nearest grid line in that direction first.
    static func stepped(_ displayValue: Double, by step: Double, up: Bool) -> Double {
        guard step > 0 else { return displayValue }
        let position = displayValue / step
        let tolerance = 1e-6
        let nextPosition: Double
        if up {
            nextPosition = (position + tolerance).rounded(.down) + 1
        } else {
            nextPosition = (position - tolerance).rounded(.up) - 1
        }
        return max(0, ((nextPosition * step) * 100).rounded() / 100)
    }
}
