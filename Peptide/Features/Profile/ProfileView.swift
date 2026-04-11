import SwiftUI

struct ProfileView: View {
    @State private var viewModel = ProfileViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    ProfileHeader(
                        name: viewModel.profile.name,
                        memberDuration: viewModel.memberDuration,
                        protocolCount: MockProtocols.all.count,
                        peptideCount: MockPeptides.all.count,
                        daysLogged: viewModel.daysLogged
                    )
                    .sectionAppear(index: 0)

                    GoalsSectionCard(
                        availableGoals: viewModel.availableGoals,
                        selectedGoals: viewModel.selectedGoals,
                        onToggle: viewModel.toggleGoal
                    )
                    .sectionAppear(index: 1)

                    HealthConnectionCard(isConnected: viewModel.profile.healthConnected)
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
}

#Preview {
    ProfileView()
        .preferredColorScheme(.dark)
}
