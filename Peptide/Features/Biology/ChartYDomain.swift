import Foundation

/// Y-axis domain for trend charts of values that sit far from zero.
/// Left to itself Swift Charts starts the axis at zero, which flattens a
/// 71–73 kg series into the top few percent of the plot.
enum ChartYDomain {
    /// Share of the values' spread added above and below.
    static let paddingFraction: Double = 0.15

    /// The spread of `values` padded by `paddingFraction` of it, or by
    /// `minimumPadding` when that is larger so a flat series still has
    /// room (one unit if both are zero). Never dips below zero for
    /// non-negative data. Nil without a finite value.
    static func padded(_ values: [Double], minimumPadding: Double) -> ClosedRange<Double>? {
        let finite = values.filter(\.isFinite)
        guard let low = finite.min(), let high = finite.max() else { return nil }
        let spreadPad = max((high - low) * paddingFraction, minimumPadding)
        let pad = spreadPad > 0 ? spreadPad : 1
        let lower = low >= 0 ? max(0, low - pad) : low - pad
        return lower...(high + pad)
    }
}
