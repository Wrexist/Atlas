import SwiftUI

struct ProfileView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var storeService = StoreService.shared
    @AppStorage(HealthSyncSettings.enabledKey) private var healthActivitySync = false
    @AppStorage(HealthSyncSettings.nutritionEnabledKey) private var healthNutritionWrite = false
    /// Set when turning on a Health write toggle came back refused.
    @State private var healthWriteRefused = false
    @State private var healthDataVisible = true
    @State private var authService = AuthService.shared
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
                        daysLogged: dataStore.totalDaysLogged,
                        workoutCount: workoutCount,
                        avatarImageData: dataStore.profile.avatarImageData,
                        bio: dataStore.profile.bio,
                        onEdit: { showProfileCustomization = true }
                    )
                    .sectionAppear(index: 0)

                    if StoreService.paywallEnabled {
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
                    }

                    // Earned Atlas Score — the rewards identity. Taps open
                    // the full progress view, where the achievement badges
                    // it sums up live.
                    ProfileLevelCard(onTap: { showProgress = true })
                        .sectionAppear(index: 2)

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
                            Task { healthWriteRefused = !(await dataStore.setHealthKitNutritionEnabled(enabled)) }
                        },
                        activitySyncEnabled: healthActivitySync,
                        onToggleActivitySync: { enabled in
                            Task { healthWriteRefused = !(await dataStore.setHealthActivitySyncEnabled(enabled)) }
                        },
                        writeAccessRefused: healthWriteRefused,
                        healthDataVisible: healthDataVisible,
                        onConnect: connectHealthKit
                    )
                    .scrollReveal()

                    // Protocol tools are secondary: one quiet row closes
                    // the page and the tools sit a tap in. Reachable,
                    // never promoted.
                    NavigationLink {
                        ProfileProtocolToolsView(dismissProfile: dismiss)
                    } label: {
                        GlassEntryRowLabel(icon: "flask.fill", title: "Protocols")
                    }
                    .buttonStyle(.cardPress)
                    .padding(.top, Spacing.lg)
                    .scrollReveal()
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
                .readableContentWidth()
            }
            .pageBackground()
            .navigationTitle("Profile")
            .solidTopScrollEdge()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        // Ink, like every other bar glyph; the accent is
                        // kept for the one confirming action.
                        Image(systemName: "gearshape")
                            .foregroundStyle(AppColor.textPrimary)
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
            // Re-checked on return from iOS Settings too, where the notice's
            // own button sends the user to grant read access.
            .task(id: "\(dataStore.profile.healthConnected)-\(scenePhase)") {
                guard dataStore.profile.healthConnected, scenePhase == .active else { return }
                healthDataVisible = await HealthKitService.shared.hasReadableData(days: 30)
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
                    .liquidGlassPresentation()
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

/// The protocol tools behind Profile's one "Protocols" row: the
/// Library, the reconstitution calculator and the cycle card share.
private struct ProfileProtocolToolsView: View {
    /// Profile's own dismiss: the Library opens only once the Profile
    /// sheet is gone, and this pushed view's dismiss would only pop it.
    let dismissProfile: DismissAction

    @Environment(DataStore.self) private var dataStore
    @State private var showReconstitutionCalculator = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.sm) {
                PeptideLibraryEntryCard(dismissProfile: dismissProfile)

                // The calculator only matters to someone running a protocol.
                if !dataStore.protocols.isEmpty {
                    ReconstitutionEntryCard(onTap: { showReconstitutionCalculator = true })
                }

                CycleCardShareSection()
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.lg)
            .readableContentWidth()
        }
        .pageBackground()
        .navigationTitle("Protocols")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showReconstitutionCalculator) {
            ReconstitutionSheet(onClose: { showReconstitutionCalculator = false })
        }
    }
}

#Preview {
    ProfileView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
