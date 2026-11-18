import SwiftUI

/// "Chest · 12 of 12 sets this week" for each muscle the workout trained,
/// so the recap says how close each one is to its weekly growth target.
struct RecapWeeklyVolume: View {
    let session: WorkoutSession

    @AppStorage("experienceLevel") private var storedExperience = "beginner"
    @State private var rows: [Row] = []

    private struct Row: Identifiable {
        let target: SessionBuilderEngine.Target
        let sets: Int
        var id: SessionBuilderEngine.Target { target }
    }

    private var goal: Int {
        Int(MuscleVolumeTargets.weeklySets(for: ProgramRequest.experience(fromRaw: storedExperience)).lowerBound)
    }

    var body: some View {
        Group {
            if !rows.isEmpty {
                RecapCard {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Weekly volume").font(AppFont.headline)
                        ForEach(rows) { row in
                            HStack {
                                Text(row.target.displayName)
                                Spacer()
                                Text("\(row.sets) of \(goal) sets")
                                    .foregroundStyle(row.sets >= goal ? AppColor.positive : AppColor.textSecondary)
                                    .fixedSize()
                            }
                            .font(AppFont.subheadline)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        // The whole session, not its id: an edit from the summary keeps the
        // id but changes what was trained.
        .task(id: session) { await load() }
    }

    private func load() async {
        let library = ExerciseLibrary.shared
        await library.load()
        let now = session.finishedAt ?? Date()
        let calendar = Calendar.current
        // Only the heat map's seven-day window, not the whole history.
        let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        let history = TrainOverviewView.finishedHistory(
            SwiftDataRepository.shared.loadWorkoutSessions(startedBetween: cutoff..<now.addingTimeInterval(1))
        )
        let weekly = WeeklyMuscleHeatmap.frequencies(from: history, library: library, now: now, calendar: calendar)
        let states = SessionBuilderEngine.states(recovery: [:], weekly: weekly)
        let trained = session.exercises
            .filter { !$0.completedWorkingSets.isEmpty }
            .compactMap { library.lookup(id: $0.exerciseID) }
            .reduce(into: Set<SessionBuilderEngine.Target>()) { $0.formUnion(SessionBuilderEngine.targets(of: $1)) }
        rows = SessionBuilderEngine.Target.allCases
            .filter(trained.contains)
            .map { Row(target: $0, sets: Int((states[$0]?.weeklySets ?? 0).rounded())) }
    }
}
