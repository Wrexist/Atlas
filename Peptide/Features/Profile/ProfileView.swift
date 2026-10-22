import SwiftUI

struct ProfileView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var storeService = StoreService.shared
    @State private var achievementService = AchievementService.shared
    @AppStorage(HealthSyncSettings.enabledKey) private var healthActivitySync = false
    @AppStorage(HealthSyncSettings.nutritionEnabledKey) private var healthNutritionWrite = false
    @State private var authService = AuthService.shared
    @State private var showReconstitutionCalculator = false
    @State private var showProfileCustomization = false
    @State private var showProgress = false
    /// Read once on appear rather than in `body`: the count is a
    /// SwiftData fetch, and the header only shows it to users with no
    /// protocols.
    @State private var workoutCount = 0

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
                        memberSince: dataStore.profile.memberSince,
                        protocolCount: dataStore.protocols.count,
                        daysLogged: dataStore.totalDaysLogged,
                        workoutCount: workoutCount,
                        avatarImageData: dataStore.profile.avatarImageData,
                        bio: dataStore.profile.bio,
                        onEdit: { showProfileCustomization = true }
                    )
                    .sectionAppear(index: 0)

                    Group {
                        if storeService.isProUser || storeService.isInBillingRetry {
                            SubscriptionSection()
                        } else {
                            UpgradePromptCard()
                        }
                    }
                    // A purchase made from inside this sheet swaps the
                    // card; cross-fade it rather than cut.
                    .transition(.opacity.combined(with: .scale(0.98)))
                    .appAnimation(AppAnimation.springSmooth, value: storeService.isProUser)
                    .sectionAppear(index: 1)

                    // Earned Atlas Score — the rewards identity, sitting
                    // above the achievement badges it sums up. Taps open
                    // the full progress view.
                    AtlasScoreCard(onTap: { showProgress = true })
                        .sectionAppear(index: 2)

                    AchievementsSection(achievements: achievementService.achievements)
                        .scrollReveal()

                    CycleCardShareSection()
                        .scrollReveal()

                    GoalsSectionCard(
                        goalCatalog: goalCatalog,
                        selectedKeys: Set(dataStore.profile.goals),
                        onToggle: toggleGoal
                    )
                    .scrollReveal()

                    BodyMetricsCard(
                        metrics: dataStore.profile.bodyMetrics,
                        onUpdate: { dataStore.updateBodyMetrics($0) }
                    )
                    .scrollReveal()

                    HealthConnectionCard(
                        isConnected: dataStore.profile.healthConnected,
                        nutritionWriteEnabled: healthNutritionWrite,
                        onToggleNutritionWrite: { enabled in
                            Task { await dataStore.setHealthKitNutritionEnabled(enabled) }
                        },
                        activitySyncEnabled: healthActivitySync,
                        onToggleActivitySync: { enabled in
                            Task { await dataStore.setHealthActivitySyncEnabled(enabled) }
                        },
                        onConnect: connectHealthKit
                    )
                    .scrollReveal()

                    PeptideLibraryEntryCard()
                        .scrollReveal()

                    // The calculator only matters to someone running a protocol.
                    if !dataStore.protocols.isEmpty {
                        ReconstitutionEntryCard(onTap: { showReconstitutionCalculator = true })
                            .scrollReveal()
                    }

                    // The way into Settings at the foot of Profile; the
                    // toolbar gear goes to the same place.
                    NavigationLink {
                        SettingsView()
                    } label: {
                        GlassEntryRowLabel(
                            icon: "gearshape.fill",
                            title: "Settings",
                            subtitle: Text("Training, reminders, appearance, data, account and about.")
                        )
                    }
                    .buttonStyle(ScalePressStyle(pressedScale: 0.98))
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
                .readableContentWidth()
            }
            .background(AppColor.background)
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(AppColor.accentPrimary)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
            .task { await authService.validateCredential() }
            .task { workoutCount = SwiftDataRepository.shared.workoutSessionCount() }
            .sheet(isPresented: $showReconstitutionCalculator) {
                ReconstitutionSheet(onClose: { showReconstitutionCalculator = false })
            }
            .sheet(isPresented: $showProfileCustomization) {
                ProfileCustomizationSheet()
                    .environment(dataStore)
                    .environment(appState)
                    .liquidGlassPresentation()
            }
            .sheet(isPresented: $showProgress) {
                AtlasProgressView()
                    .environment(dataStore)
            }
        }
        .presentationSizing(.page)
    }

    /// `toggleHealthConnection` requests authorization itself and refuses
    /// to flip on without a grant, so no separate pre-check is needed.
    private func connectHealthKit() async {
        _ = await dataStore.toggleHealthConnection()
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
