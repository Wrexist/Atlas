import SwiftUI

/// The large number a page leads with, unit in the page colour beside
/// it: "58 BPM". Rolls up when the page comes on screen. One VoiceOver
/// stop.
struct MetricReadout: View {
    let value: Int
    let unit: String
    let tint: Color
    let accessibilityText: String

    @ScaledMetric(relativeTo: .largeTitle) private var size = 44

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            RollingNumber(value: value)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(unit)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}
