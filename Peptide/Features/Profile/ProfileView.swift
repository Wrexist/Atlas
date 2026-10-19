import SwiftUI

struct ProfileView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var storeService = StoreService.shared
    @State private var achievementService = AchievementService.shared
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
                        memberDuration: memberDuration,
                        protocolCount: dataStore.protocols.count,
                        peptideCount: Set(dataStore.protocols.flatMap(\.peptides).map(\.id)).count,
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
                        .sectionAppear(index: 3)

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
                        nutritionWriteEnabled: dataStore.profile.healthKitNutritionEnabled,
                        onToggleNutritionWrite: { enabled in
                            Task { await dataStore.setHealthKitNutritionEnabled(enabled) }
                        },
                        onConnect: { connectHealthKit() }
                    )
                    .scrollReveal()

                    // Peptide Library (database + Protocols + AI research) —
                    // its home now that Habits took the tab-bar slot.
                    PeptideLibraryEntryCard()
                        .scrollReveal()

                    // Labs entry lives on the Biology tab (renamed
                    // from Insights in Phase 33). It's a high-
                    // engagement analytical feature, not a settings-
                    // flavoured tool, and it was hiding behind a
                    // settings tab here.

                    ReconstitutionEntryCard(onTap: { showReconstitutionCalculator = true })
                        .scrollReveal()

                    SettingsEntryRow()
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

/// The way into `SettingsView`, at the foot of Profile. The gear in the
/// toolbar goes to the same place.
private struct SettingsEntryRow: View {
    var body: some View {
        NavigationLink {
            SettingsView()
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "gearshape.fill")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .frame(width: 36, height: 36)
                    .background {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .fill(AppColor.accentPrimary.opacity(0.18))
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Training, reminders, appearance, data, account and about.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProfileView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
