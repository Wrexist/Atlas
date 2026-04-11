import SwiftUI

struct AnalyticsView: View {
    @State private var viewModel = AnalyticsViewModel()
    @Namespace private var segmentNamespace

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    GlassSegmentedControl(
                        options: TimeRange.allCases,
                        selected: $viewModel.selectedRange,
                        namespace: segmentNamespace
                    )
                    .sectionAppear(index: 0)

                    ComplianceChart(data: viewModel.complianceData)
                        .sectionAppear(index: 1)

                    WeeklyDoseChart(data: viewModel.weeklyDoseData)
                        .sectionAppear(index: 2)

                    ProgressSummaryCard(
                        totalDoses: viewModel.totalDoses,
                        compliance: viewModel.averageCompliance,
                        currentStreak: viewModel.currentStreak,
                        bestStreak: viewModel.bestStreak
                    )
                    .sectionAppear(index: 3)

                    TrendIndicator(
                        value: viewModel.complianceTrend,
                        label: "compliance this \(viewModel.selectedRange.rawValue.lowercased())"
                    )
                    .sectionAppear(index: 4)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationTitle("Analytics")
        }
    }
}

#Preview {
    AnalyticsView()
        .preferredColorScheme(.dark)
}
