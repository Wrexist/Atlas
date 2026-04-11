import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    WelcomeHeader(
                        greeting: viewModel.greeting,
                        name: viewModel.profile.name,
                        date: viewModel.dateString
                    )
                    .sectionAppear(index: 0)

                    ProtocolScoreCard(
                        score: viewModel.protocolScore,
                        completed: viewModel.completedCount,
                        total: viewModel.totalCount
                    )
                    .sectionAppear(index: 1)

                    TodayScheduleCard(
                        entries: viewModel.todayEntries,
                        onToggle: viewModel.toggleEntry
                    )
                    .sectionAppear(index: 2)

                    QuickStatsRow(
                        activeProtocols: viewModel.activeProtocols.count,
                        daysLogged: viewModel.totalDaysLogged,
                        streak: viewModel.currentStreak,
                        nextDose: viewModel.nextDose
                    )
                    .sectionAppear(index: 3)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}
