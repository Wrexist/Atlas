import Foundation

enum WatchFormat {
    /// "7h 12m", "45m": the compact form both the Sleep page and the
    /// Sleep complication use.
    static func duration(minutes: Int) -> String {
        Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}

/// Weight on the wrist: canonical kilograms in, the phone's unit out.
/// Built from `WatchData.measurementUnit`; an older phone that doesn't
/// send it gets metric, the unit the weights are stored in.
struct WatchWeightUnit {
    let isImperial: Bool

    init(_ measurementUnit: String?) {
        isImperial = measurementUnit == "imperial"
    }

    /// Mirrors `MeasurementUnit.weightSuffix`: the symbol is the same in
    /// every locale Atlas ships.
    var symbol: String { isImperial ? "lb" : "kg" }

    /// One Crown detent: the smallest plate pair in each system.
    var step: Double { isImperial ? 5 : 2.5 }

    func display(_ kilograms: Double) -> Double {
        isImperial ? kilograms * Self.poundsPerKilogram : kilograms
    }

    func kilograms(_ display: Double) -> Double {
        isImperial ? display / Self.poundsPerKilogram : display
    }

    /// "62.5", "135": to the half unit, which is as fine as plates go.
    func format(_ kilograms: Double) -> String {
        ((display(kilograms) * 2).rounded() / 2)
            .formatted(.number.precision(.fractionLength(0...1)))
    }

    private static let poundsPerKilogram = 2.20462
}
