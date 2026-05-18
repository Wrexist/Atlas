import SwiftUI

struct ProfileView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @State private var storeService = StoreService.shared
    @State private var achievementService = AchievementService.shared
    @State private var authService = AuthService.shared
    @State private var showReconstitutionCalculator = false
    @State private var showRestoreBackup = false

    /// Single source of truth for the goal catalog. Reads from
    /// OnboardingView.PrimaryGoal so a goal selected during the new
    /// onboarding flow renders as pre-selected here — previously the
    /// Profile picker used Title Case display strings while onboarding
    /// wrote camelCase rawValues, and the two sets never intersected.
    /// Both the storage key (camelCase rawValue) and the display
    /// label (`.displayName`) come from the enum so the two stay in
    /// lock-step on future expansions.
    private var goalCatalog: [GoalsSectionCard.GoalEntry] {
        OnboardingView.PrimaryGoal.allCases.map {
            GoalsSectionCard.GoalEntry(key: $0.rawValue, displayName: $0.displayName)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    ProfileHeader(
                        name: dataStore.profile.name,
                        memberDuration: memberDuration,
                        protocolCount: dataStore.protocols.count,
                        peptideCount: Set(dataStore.protocols.flatMap(\.peptides).map(\.id)).count,
                        daysLogged: dataStore.totalDaysLogged,
                        avatarImageData: dataStore.profile.avatarImageData,
                        bio: dataStore.profile.bio
                    )
                    .sectionAppear(index: 0)

                    if !storeService.isProUser {
                        UpgradePromptCard()
                            .sectionAppear(index: 1)
                    }

                    AchievementsSection(achievements: achievementService.achievements)
                        .sectionAppear(index: 2)

                    CycleCardShareSection()
                        .sectionAppear(index: 3)

                    GoalsSectionCard(
                        goalCatalog: goalCatalog,
                        selectedKeys: Set(dataStore.profile.goals),
                        hapticEnabled: dataStore.profile.hapticFeedbackEnabled,
                        onToggle: toggleGoal
                    )
                    .sectionAppear(index: 4)

                    BodyMetricsCard(
                        metrics: dataStore.profile.bodyMetrics,
                        onUpdate: { dataStore.updateBodyMetrics($0) }
                    )
                    .sectionAppear(index: 5)

                    HealthConnectionCard(
                        isConnected: dataStore.profile.healthConnected,
                        nutritionWriteEnabled: dataStore.profile.healthKitNutritionEnabled,
                        onToggleNutritionWrite: { enabled in
                            Task { await dataStore.setHealthKitNutritionEnabled(enabled) }
                        },
                        onConnect: { connectHealthKit() }
                    )
                    .sectionAppear(index: 6)

                    // Labs entry lives on the Biology tab (renamed
                    // from Insights in Phase 33). It's a high-
                    // engagement analytical feature, not a settings-
                    // flavoured tool, and it was hiding behind a
                    // settings tab here.

                    ReconstitutionEntryCard(onTap: { showReconstitutionCalculator = true })
                        .sectionAppear(index: 7)

                    WeeklySummaryToggleRow()
                        .sectionAppear(index: 8)

                    ScreenshotModeRow()
                        .sectionAppear(index: 9)

                    ExportSection()
                        .sectionAppear(index: 10)

                    RestoreBackupEntryRow(onTap: { showRestoreBackup = true })
                        .sectionAppear(index: 11)

                    AccountSection()
                        .sectionAppear(index: 12)

                    AppearanceSettings()
                        .sectionAppear(index: 13)

                    DiagnosticsSection()
                        .sectionAppear(index: 14)

                    AboutSection()
                        .sectionAppear(index: 15)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
                // iPad content width cap — matches HomeView's
                // treatment so Profile doesn't stretch full-width on
                // larger devices (Phase 5.8 partial).
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(AppColor.background)
            .navigationTitle("Profile")
            .task { await authService.validateCredential() }
            .sheet(isPresented: $showReconstitutionCalculator) {
                ReconstitutionSheet(onClose: { showReconstitutionCalculator = false })
            }
            .sheet(isPresented: $showRestoreBackup) {
                RestoreBackupSheet()
                    .environment(dataStore)
            }
            // Labs sheet + the `pendingLabsOpen` deep-link
            // consumption live on `BiologyView` now — labs sit
            // alongside the biomarker list on the Biology tab, and
            // the Home overview-card insight tap routes there.
        }
    }

    private var memberDuration: String {
        let months = Calendar.current.dateComponents([.month], from: dataStore.profile.memberSince, to: Date()).month ?? 0
        return months <= 1 ? "1 month" : "\(months) months"
    }

    private func connectHealthKit() {
        Task { @MainActor in
            // toggleHealthConnection now requests authorization internally
            // and refuses to flip ON without a grant — so we can call it
            // directly without a separate pre-check.
            _ = await dataStore.toggleHealthConnection()
        }
    }

    private func toggleGoal(_ goal: String) {
        var current = Set(dataStore.profile.goals)
        if current.contains(goal) {
            current.remove(goal)
        } else {
            current.insert(goal)
        }
        dataStore.updateGoals(current)
    }
}

#Preview {
    ProfileView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
