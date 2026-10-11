import SwiftUI

/// The large number every page leads with, unit in the page colour
/// beside it: "58 BPM", "1 840 KCAL". One VoiceOver stop.
struct MetricReadout: View {
    let value: String
    let unit: String
    let tint: Color
    let accessibilityText: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(unit)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}
