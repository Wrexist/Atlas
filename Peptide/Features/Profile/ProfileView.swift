import SwiftUI

struct ProfileView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @State private var storeService = StoreService.shared
    @State private var achievementService = AchievementService.shared
    @State private var authService = AuthService.shared
    @State private var showReconstitutionCalculator = false

    // Kept in sync with OnboardingView's `goals` array so a goal selected
    // during onboarding remains visible/editable here.
    private let availableGoals = [
        "Muscle Recovery",
        "Better Sleep",
        "Cognitive Edge",
        "Anti-Aging",
        "Fat Loss",
        "Immune Support",
        "Joint Health",
        "Stress Reduction",
    ]

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
                        availableGoals: availableGoals,
                        selectedGoals: Set(dataStore.profile.goals),
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

                    // Labs entry moved to the Insights tab in
                    // Phase 32 — it's a high-engagement analytical
                    // feature, not a settings-flavoured tool, and
                    // it was hiding behind a settings tab here.

                    ReconstitutionEntryCard(onTap: { showReconstitutionCalculator = true })
                        .sectionAppear(index: 7)

                    ExportSection()
                        .sectionAppear(index: 7)

                    AccountSection()
                        .sectionAppear(index: 8)

                    AppearanceSettings()
                        .sectionAppear(index: 9)

                    AboutSection()
                        .sectionAppear(index: 10)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationTitle("Profile")
            .task { await authService.validateCredential() }
            .sheet(isPresented: $showReconstitutionCalculator) {
                ReconstitutionSheet(onClose: { showReconstitutionCalculator = false })
            }
            // Labs sheet + the `pendingLabsOpen` deep-link
            // consumption moved to InsightsView in Phase 32 — labs
            // now live under "Insights" alongside the correlation
            // engines they share the analytical surface with.
        }
    }

    private var memberDuration: String {
        let months = Calendar.current.dateComponents([.month], from: dataStore.profile.memberSince, to: Date()).month ?? 0
        return months <= 1 ? "1 month" : "\(months) months"
    }

    private func connectHealthKit() {
        Task { @MainActor in
            let authorized = await HealthKitService.shared.requestAuthorization()
            if authorized {
                dataStore.toggleHealthConnection()
            }
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
