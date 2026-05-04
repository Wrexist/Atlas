import SwiftUI

enum TimeRange: String, CaseIterable, CustomStringConvertible {
    case week = "Week"
    case month = "Month"
    case threeMonths = "3 Months"

    var description: String { rawValue }

    /// Localized label for segmented controls. Static literals so Xcode
    /// extracts each case into the .xcstrings catalog at build time.
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .threeMonths: "3 Months"
        }
    }

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
    @Environment(AppState.self) private var appState
    @State private var selectedRange: TimeRange = .week
    @State private var showPaywall = false
    @State private var hrvSeries: [(date: Date, value: Double)] = []
    @Namespace private var segmentNamespace
    private var storeService: StoreService { StoreService.shared }

    var body: some View {
        let compliance = complianceData
        let avgCompliance = compliance.isEmpty ? 0 : compliance.map(\.compliance).reduce(0, +) / Double(compliance.count)

        NavigationStack {
            ScrollView {
                if dataStore.protocols.isEmpty {
                    emptyState
                        .padding(.horizontal, Spacing.screenPadding)
                        .padding(.top, Spacing.xxl)
                        .padding(.bottom, Spacing.xxxxl)
                } else {
                    VStack(spacing: Spacing.lg) {
                        GlassSegmentedControl(
                            options: TimeRange.allCases,
                            selected: Binding(
                                get: { selectedRange },
                                set: { newRange in
                                    if newRange != .week && !storeService.isProUser {
                                        showPaywall = true
                                    } else if newRange != selectedRange {
                                        if dataStore.profile.hapticFeedbackEnabled {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                        }
                                        selectedRange = newRange
                                    }
                                }
                            ),
                            namespace: segmentNamespace,
                            label: { $0.localizedTitle }
                        )
                        .sectionAppear(index: 0)

                        ComplianceChart(data: compliance)
                            .sectionAppear(index: 1)

                        if dataStore.profile.healthConnected && storeService.canAccessFullAnalytics {
                            HealthCorrelationChart(
                                adherence: correlationAdherence,
                                hrv: hrvSeries
                            )
                            .sectionAppear(index: 2)
                        }

                        WeeklyDoseChart(data: weeklyDoseData)
                            .sectionAppear(index: 3)

                        ProgressSummaryCard(
                            totalDoses: dataStore.totalDoses,
                            compliance: avgCompliance,
                            currentStreak: dataStore.currentStreak,
                            bestStreak: dataStore.bestStreak
                        )
                        .sectionAppear(index: 4)

                        TrendIndicator(
                            value: dataStore.complianceTrend(for: selectedRange.days),
                            label: trendLabel(for: selectedRange)
                        )
                        .sectionAppear(index: 5)

                        let allInsights = InsightEngine.generateInsights(
                            from: dataStore.entries,
                            protocols: dataStore.protocols
                        )

                        CalendarHeatmap(
                            entries: dataStore.entries,
                            days: selectedRange.days,
                            insight: heatmapInsight(from: allInsights)
                        )
                        .sectionAppear(index: 6)

                        InsightsCard(insights: allInsights)
                            .sectionAppear(index: 7)
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.bottom, Spacing.xxxxl)
                }
            }
            .background(AppColor.background)
            .navigationTitle("Analytics")
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .task(id: dataStore.profile.healthConnected) {
                guard dataStore.profile.healthConnected else {
                    hrvSeries = []
                    return
                }
                hrvSeries = await HealthKitService.shared.dailyHRV(days: 35)
            }
        }
    }

    /// 35-day per-day adherence series for the slot 3 HealthKit
    /// correlation overlay. Distinct from `complianceData` (which is
    /// gated by the segmented control's TimeRange) — slot 3 always shows
    /// the same 5-week window so HRV trends have room to read.
    private var correlationAdherence: [(date: Date, value: Double)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<35).compactMap { dayOffset in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { return nil }
            let dayEntries = dataStore.entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
            guard !dayEntries.isEmpty else { return nil }
            let value = Double(dayEntries.filter(\.completed).count) / Double(dayEntries.count)
            return (date, value)
        }.reversed()
    }

    /// Shown when the user has no protocols yet — analytics over zero data
    /// is meaningless, so we redirect them to the protocol builder instead
    /// of rendering blank charts.
    private var emptyState: some View {
        GlassCard(tinted: true) {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 44))
                    .foregroundStyle(AppColor.accentPrimary)
                    .padding(.top, Spacing.sm)

                VStack(spacing: Spacing.sm) {
                    Text("No data yet")
                        .font(AppFont.title2)
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Create a protocol and log a few doses — your compliance, streaks, and trends will appear here.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                }

                GlassButton(title: "Create a Protocol", icon: "plus", style: .primary, isFullWidth: true) {
                    withAnimation(AppAnimation.springSnappy) {
                        appState.selectedTab = .protocols
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
        }
    }

    /// Discrete localized phrase per range — avoids interpolating an English
    /// noun ("week"/"month") into the middle of a translated sentence, which
    /// breaks word order in many languages.
    private func trendLabel(for range: TimeRange) -> LocalizedStringKey {
        switch range {
        case .week: "compliance this week"
        case .month: "compliance this month"
        case .threeMonths: "compliance over 3 months"
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

    /// Pulls the most relevant single insight to pin above the heatmap.
    /// Priority: day-of-week warning > any other warning > streak
    /// positive > nothing. The heatmap loses its narrative if every
    /// possible insight crowds it, so we surface one.
    private func heatmapInsight(from insights: [InsightEngine.Insight]) -> InsightEngine.Insight? {
        if let dayPattern = insights.first(where: { $0.icon == "calendar.badge.exclamationmark" }) {
            return dayPattern
        }
        if let warning = insights.first(where: { $0.type == .warning }) {
            return warning
        }
        return insights.first(where: { $0.type == .positive })
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

#Preview("With Data") {
    AnalyticsView()
        .environment(DataStore(seedSampleData: true))
        .environment(AppState())
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    AnalyticsView()
        .environment(DataStore())
        .environment(AppState())
        .preferredColorScheme(.dark)
}
