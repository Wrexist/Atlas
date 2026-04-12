import SwiftUI

enum TimeRange: String, CaseIterable, CustomStringConvertible {
    case week = "Week"
    case month = "Month"
    case threeMonths = "3 Months"

    var description: String { rawValue }

    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        }
    }
}

struct AnalyticsView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var selectedRange: TimeRange = .week
    @State private var showPaywall = false
    @Namespace private var segmentNamespace
    private var storeService: StoreService { StoreService.shared }

    var body: some View {
        let compliance = complianceData
        let avgCompliance = compliance.isEmpty ? 0 : compliance.map(\.compliance).reduce(0, +) / Double(compliance.count)

        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    GlassSegmentedControl(
                        options: TimeRange.allCases,
                        selected: Binding(
                            get: { selectedRange },
                            set: { newRange in
                                if newRange != .week && !storeService.isProUser {
                                    showPaywall = true
                                } else {
                                    selectedRange = newRange
                                }
                            }
                        ),
                        namespace: segmentNamespace
                    )
                    .sectionAppear(index: 0)

                    ComplianceChart(data: compliance)
                        .sectionAppear(index: 1)

                    WeeklyDoseChart(data: weeklyDoseData)
                        .sectionAppear(index: 2)

                    ProgressSummaryCard(
                        totalDoses: dataStore.totalDoses,
                        compliance: avgCompliance,
                        currentStreak: dataStore.currentStreak,
                        bestStreak: dataStore.bestStreak
                    )
                    .sectionAppear(index: 3)

                    TrendIndicator(
                        value: dataStore.complianceTrend(for: selectedRange.days),
                        label: "compliance this \(selectedRange.rawValue.lowercased())"
                    )
                    .sectionAppear(index: 4)

                    CalendarHeatmap(entries: dataStore.entries, days: selectedRange.days)
                        .sectionAppear(index: 5)

                    InsightsCard(
                        insights: InsightEngine.generateInsights(
                            from: dataStore.entries,
                            protocols: dataStore.protocols
                        )
                    )
                    .sectionAppear(index: 6)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationTitle("Analytics")
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    private var complianceData: [(date: Date, compliance: Double)] {
        let calendar = Calendar.current
        let entries = dataStore.entries

        return (0..<selectedRange.days).compactMap { dayOffset in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { return nil }
            let dayEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
            guard !dayEntries.isEmpty else { return nil }
            let compliance = Double(dayEntries.filter(\.completed).count) / Double(dayEntries.count)
            return (date: date, compliance: compliance)
        }.reversed()
    }

    private var weeklyDoseData: [(day: String, count: Int)] {
        let calendar = Calendar.current
        let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let cutoff = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -selectedRange.days, to: Date()) ?? Date()
        )
        let rangeEntries = dataStore.entries.filter { $0.completed && $0.date >= cutoff }

        return (1...7).map { isoDay in
            let count = rangeEntries.filter { entry in
                let weekday = calendar.component(.weekday, from: entry.date)
                let iso = weekday == 1 ? 7 : weekday - 1
                return iso == isoDay
            }.count
            return (day: dayNames[isoDay - 1], count: count)
        }
    }
}

#Preview {
    AnalyticsView()
        .environment(DataStore())
        .preferredColorScheme(.dark)
}
