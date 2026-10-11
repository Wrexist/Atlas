import SwiftUI

/// A coloured value over a small uppercase label: "2/3 / HEALTH". Pages
/// lay these side by side under their rings so every stat row reads the
/// same way. One VoiceOver stop.
struct StatColumn: View {
    let value: String
    let label: String
    let color: Color
    let spoken: String

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(WatchMotion.update, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
