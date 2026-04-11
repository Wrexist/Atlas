import SwiftUI
import Charts

struct ComplianceChart: View {
    let data: [(date: Date, compliance: Double)]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Daily Compliance", systemImage: "chart.bar.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                Chart {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                        BarMark(
                            x: .value("Date", item.date, unit: .day),
                            y: .value("Compliance", item.compliance)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppColor.accentDark, AppColor.accentPrimary],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .cornerRadius(3)
                    }
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(AppColor.glassBorder)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v * 100))%")
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textTertiary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(data.count / 5, 1))) { _ in
                        AxisGridLine().foregroundStyle(Color.clear)
                        AxisValueLabel(format: .dateTime.day().month(.narrow))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
                .chartPlotStyle { plot in
                    plot.frame(height: 180)
                }
            }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        ComplianceChart(data: MockEntries.complianceData(days: 30))
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
