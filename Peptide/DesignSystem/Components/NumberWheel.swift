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

    init(values: [Value], selection: Binding<Value>, accessibilityLabel: Text, label: @escaping (Value) -> String) {
        self.values = values
        self._selection = selection
        self.accessibilityLabel = accessibilityLabel
        self.label = label
        _centred = State(initialValue: selection.wrappedValue)
    }

    private var height: CGFloat { rowHeight * CGFloat(NumberWheelMetrics.visibleRows) }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(values, id: \.self) { value in
                    row(value)
                }
            }
            .scrollTargetLayout()
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
        .onChange(of: centred) { _, value in
            guard let value, value != selection else { return }
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

    private func row(_ value: Value) -> some View {
        Text(label(value))
            .font(AppFont.title2)
            .monospacedDigit()
            .foregroundStyle(AppColor.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
            .onTapGesture { selection = value }
            .visualEffect { content, proxy in
                content
                    .opacity(1 - NumberWheelMetrics.offCentre(proxy) * 0.75)
                    .scaleEffect(1 - NumberWheelMetrics.offCentre(proxy) * 0.22)
            }
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

    /// How far a row sits from the wheel's middle: 0 centred, 1 at the edge.
    static func offCentre(_ row: GeometryProxy) -> CGFloat {
        let frame = row.frame(in: .scrollView(axis: .vertical))
        let half = max(row.size.height, 1) * CGFloat(visibleRows) / 2
        return min(abs(frame.midY - half) / half, 1)
    }
}
