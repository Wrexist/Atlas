import SwiftUI

/// How the estimate has moved: the engine recomputed weekly over the last
/// 30 or 90 days, drawn against a dashed line at chronological age. The
/// line draws itself in when the card appears and when the range changes.
struct BioAgeTrendCard: View {
    let points: [PerformanceAgeEngine.TrendPoint]
    let chronologicalAge: Int

    enum Window: Int, CaseIterable {
        case month = 30
        case quarter = 90

        var label: LocalizedStringKey {
            switch self {
            case .month:   "30 days"
            case .quarter: "90 days"
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var range: Window = .quarter
    @State private var drawProgress: CGFloat = 0

    private var visiblePoints: [PerformanceAgeEngine.TrendPoint] {
        guard let last = points.last?.date,
              let cutoff = Calendar.current.date(byAdding: .day, value: -range.rawValue, to: last)
        else { return [] }
        return points.filter { $0.date >= cutoff }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                BiologySectionHeader(title: "Trend")
                GlassSegmentedControl(
                    options: Window.allCases,
                    selected: $range,
                    label: { $0.label }
                )
                .fixedSize()
            }

            GlassCard {
                if visiblePoints.count >= 2 {
                    chartContent
                } else {
                    emptyContent
                }
            }
        }
        .onAppear { draw() }
        .onChange(of: range) { _, _ in
            // Commit the reset un-animated before drawing in again; set in
            // the same update, SwiftUI coalesces 0 → 1 and the line never
            // visibly redraws.
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { drawProgress = 0 }
            Task { draw() }
        }
    }

    // MARK: - Chart

    private var chartContent: some View {
        let shown = visiblePoints
        let change = (shown.last?.biologicalAge ?? 0) - (shown.first?.biologicalAge ?? 0)
        let days = spanDays(shown)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(BioAgeFormat.years(change))
                    .font(AppFont.scaled(24, weight: .bold, design: .rounded))
                    .foregroundStyle(tint(for: change))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: change))
                    .animation(reduceMotion ? nil : AppAnimation.springSmooth, value: change)
                Text(changeCaption(change, days: days))
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.textSecondary)
            }

            TrendPlot(
                points: shown,
                baseline: Double(chronologicalAge),
                tint: tint(for: change),
                drawProgress: drawProgress
            )
            .frame(height: 120)

            HStack {
                Text(shown.first.map { Self.dateFormatter.string(from: $0.date) } ?? "")
                Spacer()
                Text("Today")
            }
            .font(AppFont.scaled(11, weight: .medium))
            .foregroundStyle(AppColor.textTertiary)

            Label("Dashed line: your chronological age", systemImage: "line.diagonal")
                .font(AppFont.scaled(11, weight: .medium))
                .foregroundStyle(AppColor.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Biological age trend"))
        .accessibilityValue(Text(accessibilitySummary(shown, days: days)))
    }

    private var emptyContent: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(AppFont.scaled(20, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
                .accessibilityHidden(true)
            Text("Your trend appears once Atlas has estimates from two different weeks.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// Days the shown points actually cover. A new user's history can be
    /// far shorter than the selected window.
    private func spanDays(_ shown: [PerformanceAgeEngine.TrendPoint]) -> Int {
        guard let first = shown.first?.date, let last = shown.last?.date else { return 0 }
        return Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
    }

    private func changeCaption(_ change: Double, days: Int) -> String {
        if abs(change) < 0.05 {
            return String(localized: "Steady over \(days) days")
        }
        return change < 0
            ? String(localized: "Younger over \(days) days")
            : String(localized: "Older over \(days) days")
    }

    private func accessibilitySummary(_ shown: [PerformanceAgeEngine.TrendPoint], days: Int) -> String {
        let start = BioAgeFormat.age(shown.first?.biologicalAge ?? 0)
        let end = BioAgeFormat.age(shown.last?.biologicalAge ?? 0)
        return String(localized: "From \(start) to \(end) years over \(days) days")
    }

    private func tint(for change: Double) -> Color {
        if abs(change) < 0.05 { return AppColor.accentLight }
        return change < 0 ? AppColor.positive : AppColor.negative
    }

    private func draw() {
        if reduceMotion {
            drawProgress = 1
            return
        }
        withAnimation(AppAnimation.springGentle) { drawProgress = 1 }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()
}

/// The plot itself: a padded value range so small movements are visible
/// without exaggerating them, a dashed chronological-age baseline, and a
/// line that draws in via `trim`. Points sit at their dates, so a week the
/// engine couldn't estimate shows as a gap rather than closing up.
private struct TrendPlot: View {
    let points: [PerformanceAgeEngine.TrendPoint]
    let baseline: Double
    let tint: Color
    let drawProgress: CGFloat

    /// Never zoom tighter than ±1 year around the data, so a 0.2-year
    /// wobble doesn't fill the card and read as a swing.
    private static let minimumHalfSpan: Double = 1

    var body: some View {
        GeometryReader { geo in
            let bounds = valueBounds
            let positions = plotPoints(in: geo.size, bounds: bounds)
            ZStack(alignment: .topLeading) {
                if bounds.contains(baseline) {
                    Path { path in
                        let y = yPosition(baseline, in: geo.size, bounds: bounds)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(AppColor.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                linePath(positions)
                    .trim(from: 0, to: drawProgress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                ForEach(Array(positions.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(index == positions.count - 1 ? tint : AppColor.background)
                        .overlay { Circle().strokeBorder(tint, lineWidth: 1.5) }
                        .frame(width: index == positions.count - 1 ? 10 : 6,
                               height: index == positions.count - 1 ? 10 : 6)
                        .position(point)
                        .opacity(drawProgress >= CGFloat(index) / CGFloat(max(1, positions.count - 1)) ? 1 : 0)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var valueBounds: ClosedRange<Double> {
        let all = points.map(\.biologicalAge) + [baseline]
        let low = all.min() ?? baseline
        let high = all.max() ?? baseline
        let mid = (low + high) / 2
        let half = max(Self.minimumHalfSpan, (high - low) / 2 * 1.15)
        return (mid - half)...(mid + half)
    }

    private func yPosition(_ value: Double, in size: CGSize, bounds: ClosedRange<Double>) -> CGFloat {
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0 else { return size.height / 2 }
        let fraction = (value - bounds.lowerBound) / span
        return size.height * CGFloat(1 - fraction)
    }

    private func plotPoints(in size: CGSize, bounds: ClosedRange<Double>) -> [CGPoint] {
        guard points.count >= 2, let first = points.first?.date, let last = points.last?.date else { return [] }
        let inset: CGFloat = 6
        let width = max(0, size.width - inset * 2)
        let span = last.timeIntervalSince(first)
        return points.map { point in
            let fraction = span > 0 ? point.date.timeIntervalSince(first) / span : 0
            return CGPoint(x: inset + width * CGFloat(fraction),
                           y: yPosition(point.biologicalAge, in: size, bounds: bounds))
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }
}

#Preview {
    let today = Calendar.current.startOfDay(for: Date())
    let ages: [Double] = [36.1, 35.9, 35.8, 35.4, 35.5, 35.1, 34.9, 34.8, 34.6, 34.7, 34.4, 34.2, 34.1, 33.9]
    let points = ages.enumerated().map { index, age in
        PerformanceAgeEngine.TrendPoint(
            date: Calendar.current.date(byAdding: .day, value: (index - ages.count + 1) * 7, to: today) ?? today,
            biologicalAge: age
        )
    }
    return ScrollView {
        BioAgeTrendCard(points: points, chronologicalAge: 35)
            .padding(Spacing.screenPadding)
    }
    .background(AppColor.background)
}
