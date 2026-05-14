import SwiftUI
import Charts

/// Slot 3 of the App Store screenshot deck: HRV (cyan) overlaid on
/// adherence % (emerald) over a 5-week window. Two normalised lines on
/// a 0…1 vertical axis so they're directly visually comparable —
/// adherence is already 0…1, HRV is rescaled by its own min/max.
///
/// The "Read-only · Never written to Health" chip is critical for App
/// Review (slot 3 ships with this disclosure baked into the screenshot,
/// not as a Figma overlay).
struct HealthCorrelationChart: View {
    let adherence: [(date: Date, value: Double)]
    let hrv: [(date: Date, value: Double)]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header
                if adherence.isEmpty && hrv.isEmpty {
                    emptyState
                } else {
                    chart
                    legend
                    metricsRow
                }
                readOnlyChip
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Label("HealthKit Correlation", systemImage: "waveform.path.ecg.rectangle.fill")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            Text("5 weeks")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "heart.text.square",
            title: "No HealthKit data yet",
            message: "Connect Apple Health to overlay your HRV against your adherence.",
            style: .compact
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
    }

    private var chart: some View {
        let normalisedHRV = normalise(hrv)
        return Chart {
            ForEach(adherence, id: \.date) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Adherence", point.value),
                    series: .value("Series", "Adherence")
                )
                .foregroundStyle(adherenceColor)
                .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)

                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Adherence", point.value),
                    series: .value("Series", "Adherence-fill")
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [adherenceColor.opacity(0.18), adherenceColor.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
            }

            ForEach(normalisedHRV, id: \.date) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("HRV", point.value),
                    series: .value("Series", "HRV")
                )
                .foregroundStyle(hrvColor)
                .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [6, 4]))
                .interpolationMethod(.monotone)

                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("HRV", point.value),
                    series: .value("Series", "HRV-fill")
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [hrvColor.opacity(0.18), hrvColor.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: 0...1)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { value in
                AxisGridLine()
                    .foregroundStyle(AppColor.glassBorder)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(weekLabel(for: date))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.frame(height: 180)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("HRV overlaid on adherence over 5 weeks")
    }

    private var legend: some View {
        HStack(spacing: Spacing.lg) {
            legendDot(color: adherenceColor, label: "Adherence", style: .solid)
            legendDot(color: hrvColor, label: "HRV", style: .dashed)
            Spacer()
        }
    }

    private var metricsRow: some View {
        HStack(spacing: Spacing.lg) {
            metricChip("Heart Rate")
            metricChip("HRV")
            metricChip("Sleep")
            metricChip("Activity")
        }
    }

    private var readOnlyChip: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(AppColor.accentPrimary)
            Text("Read-only · Never written to Health")
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background {
            Capsule().fill(AppColor.glassTint)
        }
        .overlay {
            Capsule().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Helpers

    private var adherenceColor: Color { Color(hex: 0x4ADE80) }
    private var hrvColor: Color { Color(hex: 0x38BDF8) }

    private func metricChip(_ label: LocalizedStringKey) -> some View {
        Text(label)
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textTertiary)
    }

    private func legendDot(color: Color, label: LocalizedStringKey, style: LegendStyle) -> some View {
        HStack(spacing: Spacing.xs) {
            switch style {
            case .solid:
                Capsule()
                    .fill(color)
                    .frame(width: 14, height: 3)
            case .dashed:
                Capsule()
                    .stroke(color, style: StrokeStyle(lineWidth: 3, dash: [3, 2]))
                    .frame(width: 16, height: 3)
            }
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private enum LegendStyle { case solid, dashed }

    /// Rescales an arbitrary numeric series into [0, 1] so the HRV line
    /// shares a vertical scale with adherence — visual correlation at the
    /// cost of absolute readability. Trades off intentionally: this slide
    /// is "do they move together," not "what's my HRV today."
    private func normalise(_ series: [(date: Date, value: Double)]) -> [(date: Date, value: Double)] {
        guard let minValue = series.map(\.value).min(),
              let maxValue = series.map(\.value).max(),
              maxValue > minValue else {
            return series.map { ($0.date, 0.5) }
        }
        let span = maxValue - minValue
        return series.map { (date, raw) in
            (date, (raw - minValue) / span)
        }
    }

    private func weekLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayDiff = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today).day ?? 0
        let weeks = Int((Double(dayDiff) / 7.0).rounded())
        switch weeks {
        case 0: return "Now"
        case 1: return "1w"
        default: return "\(weeks)w"
        }
    }
}

#Preview {
    let now = Date()
    let calendar = Calendar.current
    let adherence = (0..<35).compactMap { offset -> (date: Date, value: Double)? in
        guard let date = calendar.date(byAdding: .day, value: -34 + offset, to: now) else { return nil }
        let value = 0.55 + Double(offset) * 0.011 + sin(Double(offset) / 3.0) * 0.05
        return (date, min(max(value, 0), 1))
    }
    let hrv = (0..<35).compactMap { offset -> (date: Date, value: Double)? in
        guard let date = calendar.date(byAdding: .day, value: -34 + offset, to: now) else { return nil }
        return (date, 45.0 + Double(offset) * 0.5 + sin(Double(offset) / 4.0) * 3.0)
    }
    return ZStack {
        AppColor.background.ignoresSafeArea()
        HealthCorrelationChart(adherence: adherence, hrv: hrv)
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
