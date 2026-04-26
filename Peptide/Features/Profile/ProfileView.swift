import SwiftUI

struct ProfileView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var storeService = StoreService.shared
    @State private var achievementService = AchievementService.shared
    @State private var authService = AuthService.shared

    private let availableGoals = [
        "Muscle Recovery",
        "Better Sleep",
        "Cognitive Enhancement",
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
                        daysLogged: dataStore.totalDaysLogged
                    )
                    .sectionAppear(index: 0)

                    if !storeService.isProUser {
                        UpgradePromptCard()
                            .sectionAppear(index: 1)
                    }

                    TutorialCard()
                        .sectionAppear(index: 2)

                    AchievementsSection(achievements: achievementService.achievements)
                        .sectionAppear(index: 3)

                    GoalsSectionCard(
                        availableGoals: availableGoals,
                        selectedGoals: Set(dataStore.profile.goals),
                        onToggle: toggleGoal
                    )
                    .sectionAppear(index: 4)

                    HealthConnectionCard(
                        isConnected: dataStore.profile.healthConnected,
                        onConnect: { connectHealthKit() }
                    )
                    .sectionAppear(index: 5)

                    ExportSection()
                        .sectionAppear(index: 6)

                    AccountSection()
                        .sectionAppear(index: 7)

                    AppearanceSettings()
                        .sectionAppear(index: 8)

                    AboutSection()
                        .sectionAppear(index: 9)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationTitle("Profile")
            .task { await authService.validateCredential() }
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
