import SwiftUI

/// A vertical wheel of values: drag or flick it, and the row that comes
/// to rest in the middle is the selection. Rows fade and shrink away from
/// the centre, each new centre row ticks a selection haptic, and a tap on
/// a nearby row turns the wheel to it. VoiceOver reads it as one
/// adjustable element (swipe up or down to change).
///
/// The wheel draws no selection band of its own, so several wheels side
/// by side can share one band behind them (`NumberWheelBand`).
struct NumberWheel<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let accessibilityLabel: Text
    let label: (Value) -> String

    @ScaledMetric(relativeTo: .title2) private var rowHeight: CGFloat = NumberWheelMetrics.rowHeight
    @State private var centred: Value?
    @State private var phase: ScrollPhase = .idle

    init(values: [Value], selection: Binding<Value>, accessibilityLabel: Text, label: @escaping (Value) -> String) {
        self.values = values
        self._selection = selection
        self.accessibilityLabel = accessibilityLabel
        self.label = label
        _centred = State(initialValue: selection.wrappedValue)
    }

    private var height: CGFloat { rowHeight * CGFloat(NumberWheelMetrics.visibleRows) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                let centreIndex = values.firstIndex(of: centred ?? selection) ?? 0
                LazyVStack(spacing: 0) {
                    ForEach(Array(values.enumerated()), id: \.element) { index, value in
                        row(value, stepsFromCentre: abs(index - centreIndex))
                    }
                }
                .scrollTargetLayout()
            }
            // The initial scroll position lands the value at the bottom
            // edge, not the middle; scroll it to the band explicitly.
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $centred, anchor: .center)
        // Two rows of margin above and below let the first and last
        // values reach the middle.
        .contentMargins(.vertical, rowHeight * CGFloat(NumberWheelMetrics.visibleRows / 2), for: .scrollContent)
        .frame(height: height)
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.3),
                .init(color: .black, location: 0.7),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .onScrollPhaseChange { old, new in
            phase = new
            // A programmatic turn can come to rest a row short; the
            // selection it was turning to wins.
            if old == .animating, new == .idle, centred != selection { centred = selection }
        }
        .onChange(of: centred) { _, value in
            // Only a finger moves the selection. While a programmatic turn
            // animates, the position passes every row in between, and
            // writing those back would stop a 60 → 62.5 step at 61.
            guard phase != .animating, let value, value != selection else { return }
            selection = value
        }
        .onChange(of: selection) { _, value in
            guard value != centred else { return }
            AppAnimation.with(AppAnimation.springSnappy) { centred = value }
        }
        .appSensoryFeedback(.selection, trigger: centred)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text(label(selection)))
        .accessibilityAdjustableAction { direction in
            guard let index = values.firstIndex(of: selection) else { return }
            switch direction {
            case .increment: if index + 1 < values.count { selection = values[index + 1] }
            case .decrement: if index > 0 { selection = values[index - 1] }
            @unknown default: break
            }
        }
    }

    private func row(_ value: Value, stepsFromCentre: Int) -> some View {
        let text: Text = Text(verbatim: label(value))
        let fade: Double = NumberWheelMetrics.opacity(stepsFromCentre: stepsFromCentre)
        let scale: CGFloat = NumberWheelMetrics.scale(stepsFromCentre: stepsFromCentre)
        return text
            .font(AppFont.title2)
            .foregroundStyle(AppColor.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .monospacedDigit()
            .opacity(fade)
            .scaleEffect(scale)
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
            .onTapGesture { selection = value }
    }
}

/// The band behind the wheels' middle row, shared by wheels side by side.
/// Place it inside the same Dynamic Type environment as the wheels so its
/// height scales with their rows.
struct NumberWheelBand: View {
    @ScaledMetric(relativeTo: .title2) private var rowHeight: CGFloat = NumberWheelMetrics.rowHeight

    var body: some View {
        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
            .fill(AppColor.surfaceSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .stroke(AppColor.glassBorder, lineWidth: 0.5)
            )
            .frame(height: rowHeight)
            .accessibilityHidden(true)
    }
}

enum NumberWheelMetrics {
    /// One wheel row at the default text size, scaled with `.title2`.
    static let rowHeight: CGFloat = 44
    /// Rows shown at once; odd, so one sits in the middle.
    static let visibleRows = 5

    /// Rows fade and shrink with each step away from the middle row.
    static func opacity(stepsFromCentre steps: Int) -> Double {
        [1, 0.5, 0.25][min(steps, 2)]
    }

    static func scale(stepsFromCentre steps: Int) -> CGFloat {
        [1, 0.88, 0.78][min(steps, 2)]
    }
}
