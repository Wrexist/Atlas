import SwiftUI

struct HomeView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @State private var selectedEntry: ProtocolEntry?
    @State private var selectedAlert: StackRecommendationEngine.Warning?
    @State private var adjustingAlert: StackRecommendationEngine.Warning?
    @State private var showAchievementToast = false
    @State private var toastAchievement: Achievement?
    @State private var achievementService = AchievementService.shared
    /// Observed directly so the notification banner reacts to a fresh
    /// schedule report. DataStore exposes `notificationReport` as a passthrough,
    /// but a computed read from a non-observed singleton wouldn't re-render
    /// the View on its own.
    @State private var notificationService = NotificationService.shared
    @State private var showPaywall = false
    @State private var showProfileCustomization = false
    /// Cycle-milestone prompt state. Both are nil unless the
    /// CycleMilestoneService has surfaced a pending (protocol,
    /// milestone) pair on appear; the prompt sheet routes into the
    /// share preview by setting `milestoneShareProtocol`, which drives
    /// a separate `.sheet(item:)` so SwiftUI cleanly chains the two
    /// modals across runloop ticks.
    @State private var milestonePrompt: MilestonePromptItem?
    @State private var milestoneShareProtocol: PeptideProtocol?
    @Environment(\.requestReview) private var requestReview

    private static let reviewWorthyAchievements: Set<String> = [
        "streak_7", "streak_14", "streak_30", "streak_90",
        "fifty_doses", "hundred_doses", "five_hundred_doses",
        "month_logged"
    ]

    private var todayStats: (entries: [ProtocolEntry], score: Double, completed: Int, total: Int) {
        let entries = dataStore.todayEntries
        let completed = entries.filter(\.completed).count
        let total = entries.count
        let score = total > 0 ? Double(completed) / Double(total) : 0
        return (entries, score, completed, total)
    }

    private var dailyPlan: DailyScheduleEngine.DailyPlan {
        DailyScheduleEngine.plan(for: dataStore.todayEntries)
    }

    /// Touches `notificationService.lastReport` so the View takes a SwiftUI
    /// observation dependency on it — without this, the dependency is on
    /// DataStore.notificationReport which reads a non-observed singleton
    /// and so the banner won't refresh after a reschedule.
    private var shouldShowNotificationBanner: Bool {
        notificationService.lastReport.hasAnyIssue
    }

    var body: some View {
        let stats = todayStats
        let warnings = dataStore.stackWarnings
        let recommendations = dataStore.stackRecommendations
        let plannerSuggestions = SmartCyclePlanner.suggestions(
            protocols: dataStore.protocols,
            entries: dataStore.entries
        )
        let completeness = dataStore.stackCompleteness
        let transitions = dataStore.cycleTransitions
        let overview = TodayOverviewSnapshot.build(from: dataStore)

        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    WelcomeHeader(
                        greeting: greeting,
                        name: dataStore.profile.name,
                        date: dateString,
                        avatarImageData: dataStore.profile.avatarImageData,
                        onAvatarTap: {
                            if dataStore.profile.hapticFeedbackEnabled {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            showProfileCustomization = true
                        }
                    )
                    .sectionAppear(index: 0)

                    // Observed via the @State notificationService so the banner
                    // re-renders when a reschedule writes a fresh report. Reading
                    // through DataStore's passthrough wouldn't trigger redraw.
                    if shouldShowNotificationBanner,
                       let report = dataStore.notificationReport {
                        NotificationIssueBanner(
                            report: report,
                            droppedProtocolNames: dataStore.droppedReminderProtocolNames
                        )
                        .sectionAppear(index: 0)
                    }

                    if overview.hasAnySignal {
                        TodayOverviewCard(
                            snapshot: overview,
                            userName: dataStore.profile.name,
                            hapticsEnabled: dataStore.profile.hapticFeedbackEnabled,
                            onTapHero: { dose in
                                guard let dose else { return }
                                selectedEntry = dose
                            },
                            onTapInsight: { insight in
                                if case .latestLab = insight {
                                    appState.pendingLabsOpen = true
                                    appState.selectedTab = .profile
                                }
                            }
                        )
                        .sectionAppear(index: 0)
                    }

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

                        DailyPlanCard(
                            plan: dailyPlan,
                            onTapDose: { entry in selectedEntry = entry }
                        )
                        .sectionAppear(index: 2)

                        TodayScheduleCard(
                            entries: stats.entries,
                            onToggle: { entry in dataStore.toggleEntry(entry.id) },
                            onTap: { entry in selectedEntry = entry }
                        )
                        .sectionAppear(index: 3)

                        QuickStatsRow(
                            activeProtocols: dataStore.activeProtocols.count,
                            daysLogged: dataStore.totalDaysLogged,
                            compliance: Int(dataStore.averageCompliance * 100),
                            nextDose: dataStore.nextDose
                        )
                        .sectionAppear(index: 4)

                        VialShelfCard(peptides: dataStore.stackPeptides)
                            .sectionAppear(index: 5)

                        if let completeness {
                            StackCompletenessCard(completeness: completeness)
                                .sectionAppear(index: 6)
                        }

                        if !transitions.isEmpty {
                            CycleTransitionCard(transitions: transitions)
                                .sectionAppear(index: 7)
                        }

                        if !warnings.isEmpty {
                            StackWarningCard(
                                warnings: warnings,
                                hapticEnabled: dataStore.profile.hapticFeedbackEnabled,
                                onSelect: { selectedAlert = $0 }
                            )
                            .sectionAppear(index: 8)
                        }

                        SmartCyclePlannerCard(suggestions: plannerSuggestions)
                            .sectionAppear(index: 9)

                        if !recommendations.isEmpty {
                            RecommendedPeptidesCard(
                                recommendations: recommendations,
                                activeProtocols: dataStore.activeProtocols,
                                hapticEnabled: dataStore.profile.hapticFeedbackEnabled
                            )
                            .sectionAppear(index: 10)
                        }

                        if dataStore.profile.healthConnected {
                            HealthSummaryCard()
                                .sectionAppear(index: 11)
                        }

                        if let topInsight = dataStore.topInsight {
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
                            .sectionAppear(index: 12)
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
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
                .liquidGlassPresentation()
            }
            .sheet(item: $selectedAlert) { warning in
                StackAlertDetailSheet(
                    warning: warning,
                    peptideDatabase: dataStore.peptideDatabase,
                    hapticEnabled: dataStore.profile.hapticFeedbackEnabled,
                    onPrimaryAction: {
                        if canAdjustStack(for: warning) {
                            // Defer until the alert sheet has finished dismissing — SwiftUI can't
                            // chain two sheets in the same runloop tick.
                            Task { @MainActor in
                                try? await Task.sleep(for: AppAnimation.sheetDismissDelay)
                                adjustingAlert = warning
                            }
                        } else {
                            appState.selectedTab = .protocols
                        }
                    }
                )
            }
            .sheet(item: $adjustingAlert) { warning in
                let candidates = StackAdjustmentEngine.candidateProtocols(
                    affectedAbbreviations: warning.peptides,
                    in: dataStore.activeProtocols
                )
                StackAdjustmentSheet(
                    warning: warning,
                    candidateProtocols: candidates,
                    allActiveProtocols: dataStore.activeProtocols,
                    peptideDatabase: dataStore.peptideDatabase,
                    hapticEnabled: dataStore.profile.hapticFeedbackEnabled,
                    onApply: applyStackAdjustment
                )
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .liquidGlassPresentation()
            }
            .sheet(isPresented: $showProfileCustomization) {
                ProfileCustomizationSheet()
                    .environment(dataStore)
                    .environment(appState)
                    .liquidGlassPresentation()
            }
            .sheet(item: $milestonePrompt) { item in
                CycleMilestonePromptSheet(
                    proto: item.proto,
                    milestone: item.milestone,
                    onShare: {
                        CycleMilestoneService.shared.markShown(item.milestone, for: item.proto.id)
                        let proto = item.proto
                        milestonePrompt = nil
                        // Defer one runloop tick so the prompt sheet has
                        // finished dismissing before the share sheet mounts —
                        // SwiftUI can't chain two sheets in the same tick.
                        Task { @MainActor in
                            try? await Task.sleep(for: AppAnimation.sheetDismissDelay)
                            milestoneShareProtocol = proto
                        }
                    },
                    onDismiss: {
                        CycleMilestoneService.shared.markShown(item.milestone, for: item.proto.id)
                        milestonePrompt = nil
                    }
                )
                .liquidGlassPresentation(detents: [.medium])
            }
            .sheet(item: $milestoneShareProtocol) { proto in
                ShareCardSheet(subject: .singleProtocol(proto))
                    .environment(dataStore)
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
                    if Self.reviewWorthyAchievements.contains(newId) {
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            ReviewPromptService.shared.requestReviewIfEligible(using: requestReview)
                        }
                    }
                }
            }
            .onChange(of: stats.score) { oldScore, newScore in
                if oldScore < 1.0, newScore >= 1.0, stats.total > 0 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        ReviewPromptService.shared.requestReviewIfEligible(using: requestReview)
                    }
                }
            }
            .onAppear { checkMilestonePrompt() }
        }
    }

    /// Surfaces the next pending Day-7 / Day-30 / cycle-complete prompt
    /// when Home becomes visible. Skipped when another sheet is already
    /// up so we never stack modals on top of each other.
    private func checkMilestonePrompt() {
        guard milestonePrompt == nil,
              milestoneShareProtocol == nil,
              !showPaywall,
              !showProfileCustomization
        else { return }

        guard let pending = CycleMilestoneService.shared.pendingMilestone(in: dataStore.protocols) else {
            return
        }
        // Defer slightly so the home tab's appear animation lands first.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard milestonePrompt == nil else { return }
            milestonePrompt = MilestonePromptItem(proto: pending.proto, milestone: pending.milestone)
        }
    }

    private struct MilestonePromptItem: Identifiable {
        let proto: PeptideProtocol
        let milestone: CycleMilestoneService.Milestone
        var id: String { "\(proto.id.uuidString):\(milestone.rawValue)" }
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
                        .accessibilityHidden(true)              // Text below carries the meaning
                    Text("Browse the Peptides tab to explore the database")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
        }
    }

    private func canAdjustStack(for warning: StackRecommendationEngine.Warning) -> Bool {
        let candidates = StackAdjustmentEngine.candidateProtocols(
            affectedAbbreviations: warning.peptides,
            in: dataStore.activeProtocols
        )
        return !candidates.isEmpty
    }

    private func applyStackAdjustment(_ result: StackAdjustmentResult) {
        guard let source = dataStore.activeProtocols.first(where: { $0.id == result.sourceProtocolId }) else { return }

        dataStore.updateProtocol(
            id: source.id,
            name: source.name,
            peptides: result.updatedPeptides,
            schedule: source.schedule,
            peptideSchedules: source.peptideSchedules,
            cycleLengthWeeks: source.cycleLengthWeeks,
            notes: source.notes
        )

        var deferredPaywall = false
        for move in result.moves {
            switch move.destination {
            case .discard:
                continue
            case .moveTo(let protocolId, _, _):
                dataStore.addPeptide(move.peptide, toProtocolId: protocolId)
            case .createStack:
                if StoreService.shared.requiresPro(activeProtocolCount: dataStore.activeProtocols.count) {
                    deferredPaywall = true
                    continue
                }
                let newStack = PeptideProtocol(
                    id: UUID(),
                    name: "\(move.peptide.abbreviation) Solo",
                    peptides: [move.peptide],
                    schedule: source.schedule,
                    cycleLengthWeeks: source.cycleLengthWeeks,
                    startDate: Date(),
                    status: .active,
                    notes: "Spun off from \(source.name) to reduce compounding side effects."
                )
                dataStore.addProtocol(newStack)
            }
        }
        if deferredPaywall { showPaywall = true }
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
