import SwiftUI
import Charts

/// A bounded history window; never presents a failed read as no training.
struct ExerciseHistorySection: View {
    let exercise: Exercise
    @Environment(DataStore.self) private var dataStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var visits: [ExerciseHistoryEngine.Visit] = []
    @State private var loading = true
    @State private var failed = false
    @State private var expanded = false
    private var unit: MeasurementUnit { dataStore.profile.bodyMetrics.unit }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Your history").font(AppFont.headline)
                Text("Last 90 days · Completed working sets")
                    .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                if loading {
                    ProgressView("Loading history…")
                } else if failed {
                    Text("Couldn't load your exercise history.")
                        .font(AppFont.callout)
                    Button("Retry", action: reload).minimumHitArea()
                } else if visits.isEmpty {
                    Text("No completed working sets for this exercise in the last 90 days. Your next saved workout will appear here.")
                        .font(AppFont.callout).foregroundStyle(AppColor.textSecondary)
                } else {
                    if visits.count > 1 { activityChart }
                    ForEach(Array(visits.prefix(expanded ? visits.count : 3))) { visit in
                        visitRow(visit)
                    }
                    if visits.count > 3 {
                        Button(expanded ? "Show recent workouts" : "Show all \(visits.count) workouts") {
                            expanded.toggle()
                        }.minimumHitArea()
                    }
                    Text("Warm-ups and unfinished sets are excluded. Set counts describe logged activity, not strength or muscle activation.")
                        .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("exercise-history")
        .task(id: dataStore.revision) { reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
    }

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Working sets · Latest \(min(visits.count, 8)) workouts")
                .font(AppFont.subheadline)
            Chart(Array(visits.prefix(8).reversed())) { visit in
                BarMark(x: .value("Workout", visit.id.uuidString),
                        y: .value("Working sets", visit.sets.count))
                    .foregroundStyle(AppColor.accentPrimary)
            }
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .frame(height: 100)
            .accessibilityHidden(true)
            Text("Oldest to newest. Exact dates and sets are listed below.")
                .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
        }
    }

    private func visitRow(_ visit: ExerciseHistoryEngine.Visit) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            NavigationLink {
                WorkoutSessionDetailView(session: visit.session)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(visit.name)
                            .font(AppFont.subheadline.weight(.semibold))
                        Text(visit.date.formatted(date: .abbreviated, time: .shortened))
                            .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }.frame(minHeight: 44)
            }
            .accessibilityHint("Opens the saved workout and editing options")
            Text("\(visit.sets.count) working sets").font(AppFont.caption)
            ForEach(visit.sets) { set in
                Text(RecapFormat.set(set, unit: unit))
                    .font(AppFont.callout).monospacedDigit()
                    .foregroundStyle(AppColor.textSecondary)
            }
            Divider()
        }
    }

    private func reload() {
        loading = true
        failed = false
        let now = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -90, to: now) else {
            loading = false
            failed = true
            return
        }
        do {
            let sessions = try SwiftDataRepository.shared.loadWorkoutRecapWeek(in: start..<now.addingTimeInterval(1))
            visits = ExerciseHistoryEngine.visits(exerciseID: exercise.id, sessions: sessions,
                                                  catalog: [exercise.id: exercise])
        } catch {
            visits = []
            failed = true
        }
        loading = false
    }
}
