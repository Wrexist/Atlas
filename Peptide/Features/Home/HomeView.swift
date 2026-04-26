import SwiftUI

struct HomeView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @State private var selectedEntry: ProtocolEntry?
    @State private var selectedAlert: StackRecommendationEngine.Warning?
    @State private var showAchievementToast = false
    @State private var toastAchievement: Achievement?
    @State private var achievementService = AchievementService.shared

    private var todayStats: (entries: [ProtocolEntry], score: Double, completed: Int, total: Int) {
        let entries = dataStore.todayEntries
        let completed = entries.filter(\.completed).count
        let total = entries.count
        let score = total > 0 ? Double(completed) / Double(total) : 0
        return (entries, score, completed, total)
    }

    private var stackPeptides: [Peptide] {
        var seen = Set<UUID>()
        return dataStore.activeProtocols.flatMap(\.peptides).filter { seen.insert($0.id).inserted }
    }

    private var stackWarnings: [StackRecommendationEngine.Warning] {
        StackRecommendationEngine.warnings(
            for: stackPeptides,
            activeProtocols: dataStore.activeProtocols
        )
    }

    private var stackRecommendations: [StackRecommendationEngine.Recommendation] {
        let context = StackRecommendationEngine.RecommendationContext(
            currentPeptides: stackPeptides,
            database: dataStore.peptideDatabase,
            goals: dataStore.profile.goals,
            activeProtocols: dataStore.activeProtocols,
            entries: dataStore.entries
        )
        return StackRecommendationEngine.recommendations(context: context)
    }

    private var stackCompleteness: StackRecommendationEngine.StackCompleteness? {
        StackRecommendationEngine.stackCompleteness(
            for: stackPeptides,
            goals: dataStore.profile.goals,
            from: dataStore.peptideDatabase
        )
    }

    private var cycleTransitions: [StackRecommendationEngine.CycleTransition] {
        StackRecommendationEngine.cycleTransitions(for: dataStore.activeProtocols)
    }

    var body: some View {
        let stats = todayStats
        let warnings = stackWarnings
        let recommendations = stackRecommendations
        let completeness = stackCompleteness
        let transitions = cycleTransitions

        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    WelcomeHeader(
                        greeting: greeting,
                        name: dataStore.profile.name,
                        date: dateString
                    )
                    .sectionAppear(index: 0)

                    if dataStore.protocols.isEmpty {
                        gettingStartedCard
                            .sectionAppear(index: 1)
                    } else {
                        ProtocolScoreCard(
                            score: stats.score,
                            completed: stats.completed,
                            total: stats.total,
                            streak: dataStore.currentStreak,
                            bestStreak: dataStore.bestStreak,
                            weeklyCompletion: dataStore.weeklyCompletion
                        )
                        .sectionAppear(index: 1)

                        TodayScheduleCard(
                            entries: stats.entries,
                            onToggle: { entry in dataStore.toggleEntry(entry.id) },
                            onTap: { entry in selectedEntry = entry }
                        )
                        .sectionAppear(index: 2)

                        QuickStatsRow(
                            activeProtocols: dataStore.activeProtocols.count,
                            daysLogged: dataStore.totalDaysLogged,
                            compliance: Int(dataStore.averageCompliance * 100),
                            nextDose: dataStore.nextDose
                        )
                        .sectionAppear(index: 3)

                        if let completeness {
                            StackCompletenessCard(completeness: completeness)
                                .sectionAppear(index: 4)
                        }

                        if !transitions.isEmpty {
                            CycleTransitionCard(transitions: transitions)
                                .sectionAppear(index: 5)
                        }

                        if !warnings.isEmpty {
                            StackWarningCard(
                                warnings: warnings,
                                hapticEnabled: dataStore.profile.hapticFeedbackEnabled,
                                onSelect: { selectedAlert = $0 }
                            )
                            .sectionAppear(index: 6)
                        }

                        if !recommendations.isEmpty {
                            RecommendedPeptidesCard(
                                recommendations: recommendations,
                                activeProtocols: dataStore.activeProtocols,
                                hapticEnabled: dataStore.profile.hapticFeedbackEnabled
                            )
                            .sectionAppear(index: 7)
                        }

                        if dataStore.profile.healthConnected {
                            HealthSummaryCard()
                                .sectionAppear(index: 8)
                        }

                        let insights = InsightEngine.generateInsights(
                            from: dataStore.entries, protocols: dataStore.protocols
                        )
                        if let topInsight = insights.first {
                            GlassCard {
                                HStack(spacing: Spacing.md) {
                                    Image(systemName: topInsight.icon)
                                        .font(.system(size: 16))
                                        .foregroundStyle(AppColor.accentPrimary)
                                        .frame(width: 28, height: 28)
                                        .background {
                                            Circle().fill(AppColor.accentPrimary.opacity(0.15))
                                        }
                                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                                        Text(topInsight.title)
                                            .font(AppFont.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(AppColor.textPrimary)
                                        Text(topInsight.description)
                                            .font(AppFont.caption)
                                            .foregroundStyle(AppColor.textSecondary)
                                    }
                                    Spacer()
                                }
                            }
                            .sectionAppear(index: 9)
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedEntry) { entry in
                DoseLoggingSheet(entry: entry) { actualDose, actualTime, site, notes in
                    dataStore.logDose(
                        entryId: entry.id,
                        actualDose: actualDose,
                        actualTime: actualTime,
                        injectionSite: site,
                        notes: notes
                    )
                }
            }
            .sheet(item: $selectedAlert) { warning in
                StackAlertDetailSheet(
                    warning: warning,
                    peptideDatabase: dataStore.peptideDatabase,
                    hapticEnabled: dataStore.profile.hapticFeedbackEnabled,
                    onPrimaryAction: {
                        appState.selectedTab = .protocols
                    }
                )
            }
            .navigationDestination(for: Peptide.self) { peptide in
                PeptideDetailView(peptide: peptide)
            }
            .overlay {
                if let achievement = toastAchievement {
                    AchievementToastView(achievement: achievement, isShowing: $showAchievementToast)
                }
            }
            .onChange(of: achievementService.latestUnlock?.id) { _, newId in
                if let newId, let achievement = achievementService.achievements.first(where: { $0.id == newId }) {
                    toastAchievement = achievement
                    withAnimation(AppAnimation.springBouncy) { showAchievementToast = true }
                }
            }
        }
    }

    private var gettingStartedCard: some View {
        GlassCard(tinted: true) {
            VStack(spacing: Spacing.xl) {
                Image(systemName: "flask.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColor.accentPrimary)

                VStack(spacing: Spacing.sm) {
                    Text("Create Your First Protocol")
                        .font(AppFont.title2)
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Set up a peptide protocol to start tracking doses, streaks, and compliance.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                }

                GlassButton(title: "Get Started", icon: "plus", style: .primary, isFullWidth: true) {
                    withAnimation(AppAnimation.springSnappy) {
                        appState.selectedTab = .protocols
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.textTertiary)
                    Text("Browse the Peptides tab to explore the database")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    private var dateString: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

#Preview("With Data") {
    HomeView()
        .environment(DataStore(seedSampleData: true))
        .environment(AppState())
        .preferredColorScheme(.dark)
}

#Preview("Empty State") {
    HomeView()
        .environment(DataStore())
        .environment(AppState())
        .preferredColorScheme(.dark)
}
