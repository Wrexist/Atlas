import SwiftUI

struct ProfileView: View {
    @Environment(DataStore.self) private var dataStore

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

                    GoalsSectionCard(
                        availableGoals: availableGoals,
                        selectedGoals: Set(dataStore.profile.goals),
                        onToggle: toggleGoal
                    )
                    .sectionAppear(index: 1)

                    HealthConnectionCard(
                        isConnected: dataStore.profile.healthConnected,
                        onConnect: { dataStore.toggleHealthConnection() }
                    )
                    .sectionAppear(index: 2)

                    AppearanceSettings()
                        .sectionAppear(index: 3)

                    AboutSection()
                        .sectionAppear(index: 4)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationTitle("Profile")
        }
    }

    private var memberDuration: String {
        let months = Calendar.current.dateComponents([.month], from: dataStore.profile.memberSince, to: Date()).month ?? 0
        return months <= 1 ? "1 month" : "\(months) months"
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
        .environment(DataStore())
        .preferredColorScheme(.dark)
}
