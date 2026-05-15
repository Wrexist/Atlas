import SwiftUI
import Charts

struct WeeklyDoseChart: View {
    let data: [(day: String, count: Int)]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Weekly Doses", systemImage: "chart.line.uptrend.xyaxis")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                Chart {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                        LineMark(
                            x: .value("Day", item.day),
                            y: .value("Doses", item.count)
                        )
                        .foregroundStyle(AppColor.accentPrimary)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        AreaMark(
                            x: .value("Day", item.day),
                            y: .value("Doses", item.count)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    AppColor.accentPrimary.opacity(0.3),
                                    AppColor.accentPrimary.opacity(0.05),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Day", item.day),
                            y: .value("Doses", item.count)
                        )
                        .foregroundStyle(AppColor.accentLight)
                        .symbolSize(30)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(AppColor.glassBorder)
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)")
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textTertiary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
                .chartPlotStyle { plot in
                    plot.frame(height: 160)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Weekly doses chart")
                .accessibilityValue(voiceOverSummary)
            }
        }
    }

    private var voiceOverSummary: String {
        guard !data.isEmpty else { return "No dose data this week." }
        let total = data.reduce(0) { $0 + $1.count }
        let parts = data.map { "\($0.day) \($0.count)" }.joined(separator: ", ")
        return "\(total) doses this week. " + parts + "."
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        WeeklyDoseChart(data: [("Mon", 4), ("Tue", 5), ("Wed", 3), ("Thu", 4), ("Fri", 5), ("Sat", 2), ("Sun", 2)])
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
