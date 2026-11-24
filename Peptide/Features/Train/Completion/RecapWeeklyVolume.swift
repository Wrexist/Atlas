import SwiftUI

/// "Chest · +4 · 12 of 12 sets this week" for each muscle the workout
/// trained: a bar that grows by exactly what this session added, so the
/// recap shows each muscle getting closer to its weekly growth target.
struct RecapWeeklyVolume: View {
    let session: WorkoutSession

    @AppStorage("experienceLevel") private var storedExperience = "beginner"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rows: [Row] = []
    @State private var grown = false
    @State private var loaded = false

    struct Row: Identifiable, Equatable {
        let target: SessionBuilderEngine.Target
        let before: Int
        let after: Int
        var id: SessionBuilderEngine.Target { target }
        var added: Int { max(after - before, 0) }
    }

    private var goal: Int {
        Int(MuscleVolumeTargets.weeklySets(for: ProgramRequest.experience(fromRaw: storedExperience)).lowerBound)
    }

    var body: some View {
        Group {
            // A zero-height stand-in until the first load: modifiers on an
            // empty Group never run, so `.task` would never fill `rows`.
            if !loaded {
                Color.clear.frame(height: 0)
            } else if !rows.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Stronger this week").font(AppFont.headline)
                                .accessibilityAddTraits(.isHeader)
                            Text("Sets toward each muscle's weekly growth target")
                                .font(AppFont.subheadline).foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(rows) { row in
                            RecapGrowthRow(row: row, goal: goal, grown: grown || reduceMotion)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        // Only the week `frequencies` counts, not the lifetime history:
        // this runs while the finish animation plays. The extra second
        // keeps a session starting exactly at `now` in the half-open range.
        let week = WeeklyMuscleHeatmap.windowStart(days: 7, now: now)..<now.addingTimeInterval(1)
        let history = TrainOverviewView.finishedHistory(
            SwiftDataRepository.shared.loadWorkoutSessions(startedBetween: week)
        )
        let others = history.filter { $0.id != session.id }
        let after = weeklySets(from: others + [session], library: library, now: now)
        let before = weeklySets(from: others, library: library, now: now)
        let trained = session.exercises
            .filter { !$0.completedWorkingSets.isEmpty }
            .compactMap { library.lookup(id: $0.exerciseID) }
            .reduce(into: Set<SessionBuilderEngine.Target>()) { $0.formUnion(SessionBuilderEngine.targets(of: $1)) }
        grown = false
        rows = SessionBuilderEngine.Target.allCases
            .filter(trained.contains)
            .map { Row(target: $0, before: before[$0] ?? 0, after: after[$0] ?? 0) }
        loaded = true
        try? await Task.sleep(for: .milliseconds(700))
        AppAnimation.with(AppAnimation.springGentle) { grown = true }
    }

    private func weeklySets(from sessions: [WorkoutSession], library: ExerciseLibrary, now: Date) -> [SessionBuilderEngine.Target: Int] {
        let weekly = WeeklyMuscleHeatmap.frequencies(from: sessions, library: library, now: now)
        return SessionBuilderEngine.states(recovery: [:], weekly: weekly)
            .mapValues { Int($0.weeklySets.rounded()) }
    }
}

/// One muscle: the sets it already had this week, plus this workout's
/// share drawn in the accent as it grows in.
private struct RecapGrowthRow: View {
    let row: RecapWeeklyVolume.Row
    let goal: Int
    let grown: Bool

    private var scale: Double { Double(max(goal, row.after, 1)) }
    private var reached: Bool { row.after >= goal }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(row.target.displayName).font(AppFont.subheadline.weight(.semibold))
                if row.added > 0 {
                    Text("+\(row.added)")
                        .font(AppFont.chipText).monospacedDigit()
                        .foregroundStyle(AppColor.accentPrimary)
                        .opacity(grown ? 1 : 0)
                }
                Spacer(minLength: Spacing.sm)
                Label {
                    Text("\(grown ? row.after : row.before) of \(goal) sets")
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(grown ? row.after : row.before)))
                } icon: {
                    if reached && grown {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(AppColor.accentPrimary)
                    }
                }
                .labelStyle(TrailingIconLabelStyle())
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize()
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.track)
                    Capsule().fill(AppColor.accentPrimary)
                        .frame(width: width * min(Double(grown ? row.after : row.before) / scale, 1))
                    Capsule().fill(AppColor.textSecondary.opacity(0.55))
                        .frame(width: width * min(Double(row.before) / scale, 1))
                }
            }
            .frame(height: Spacing.sm)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(row.target.displayName), \(row.after) of \(goal) sets this week, \(row.added) from this workout"))
    }

    private struct TrailingIconLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: Spacing.xxs) { configuration.title; configuration.icon }
        }
    }
}
