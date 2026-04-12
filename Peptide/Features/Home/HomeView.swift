import SwiftUI

struct HomeView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var selectedEntry: ProtocolEntry?

    private var todayStats: (entries: [ProtocolEntry], score: Double, completed: Int, total: Int) {
        let entries = dataStore.todayEntries
        let completed = entries.filter(\.completed).count
        let total = entries.count
        let score = total > 0 ? Double(completed) / Double(total) : 0
        return (entries, score, completed, total)
    }

    var body: some View {
        let stats = todayStats

        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    WelcomeHeader(
                        greeting: greeting,
                        name: dataStore.profile.name,
                        date: dateString
                    )
                    .sectionAppear(index: 0)

                    ProtocolScoreCard(
                        score: stats.score,
                        completed: stats.completed,
                        total: stats.total
                    )
                    .sectionAppear(index: 1)

                    TodayScheduleCard(
                        entries: stats.entries,
                        onToggle: { entry in dataStore.toggleEntry(entry.id) },
                        onLongPress: { entry in selectedEntry = entry }
                    )
                    .sectionAppear(index: 2)

                    QuickStatsRow(
                        activeProtocols: dataStore.activeProtocols.count,
                        daysLogged: dataStore.totalDaysLogged,
                        streak: dataStore.currentStreak,
                        nextDose: dataStore.nextDose
                    )
                    .sectionAppear(index: 3)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationBarTitleDisplayMode(.inline)
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
            }
        }
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

#Preview {
    HomeView()
        .environment(DataStore())
        .preferredColorScheme(.dark)
}
