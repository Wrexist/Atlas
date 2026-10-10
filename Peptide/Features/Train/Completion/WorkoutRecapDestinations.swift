import SwiftUI

struct WorkoutRecapExercisesView: View {
    let store: WorkoutRecapStore
    let unit: MeasurementUnit
    @State private var editing = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let summary = store.summary {
                    Text("\(summary.entries.count) exercises").font(AppFont.subheadline)
                    ForEach(summary.entries) { entry in
                        NavigationLink {
                            WorkoutRecapExerciseDetail(store: store, entryID: entry.id, unit: unit)
                        } label: {
                            RecapCard {
                                VStack(alignment: .leading, spacing: Spacing.md) {
                                    HStack(alignment: .top, spacing: Spacing.md) {
                                        ExerciseImageView(exercise: ExerciseLibrary.shared.lookup(id: entry.exerciseID))
                                            .frame(width: 64, height: 76)
                                        VStack(alignment: .leading, spacing: Spacing.xs) {
                                            Text(entry.name).font(AppFont.headline)
                                            Text("\(entry.sets.count) working sets").font(AppFont.subheadline)
                                            if let volume = entry.volumeKg {
                                                Text(RecapFormat.volume(volume, unit: unit)).font(AppFont.subheadline)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").accessibilityHidden(true)
                                    }
                                    ForEach(entry.sets) { set in RecapSetRow(set: set, unit: unit) }
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                    if summary.entries.isEmpty {
                        Text(summary.session.exercises.isEmpty ? "No exercise or set details were recorded for this workout." : "No completed working sets in this workout.")
                    }
                }
            }.padding(Spacing.screenPadding)
        }
        .recapScreen(title: "Exercises")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true }.minimumHitArea() }
        }
        .sheet(isPresented: $editing) {
            WorkoutSavedEditor(session: store.session, unit: unit) { edited in
                try store.saveEdits(edited)
                Task { await store.load() }
            }
        }
    }
}

struct RecapSetRow: View {
    let set: SetEntry
    let unit: MeasurementUnit
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Set \(set.index)\(set.isWarmup ? " · Warm-up" : "")\(set.completed ? "" : " · Unfinished")")
                .foregroundStyle(AppColor.recapSecondary)
            Text(RecapFormat.set(set, unit: unit)).monospacedDigit()
        }.font(AppFont.subheadline).accessibilityElement(children: .combine)
    }
}

struct WorkoutRecapExerciseDetail: View {
    let store: WorkoutRecapStore
    let entryID: UUID
    let unit: MeasurementUnit
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let entry = store.session.exercises.first(where: { $0.id == entryID }) {
                    let exercise = ExerciseLibrary.shared.lookup(id: entry.exerciseID)
                    Text(exercise?.name ?? entry.exerciseID).font(AppFont.title2)
                    Text("All logged sets").font(AppFont.headline)
                    Text("Warm-ups and unfinished sets are excluded from completion totals.")
                        .font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
                    ForEach(entry.sets.sorted { $0.index < $1.index }) { set in
                        RecapCard { RecapSetRow(set: set, unit: unit) }
                    }
                    if let note = entry.note, !note.isEmpty { Text(note).font(AppFont.body) }
                }
            }.padding(Spacing.screenPadding)
        }.recapScreen(title: "Exercise details")
    }
}

struct WorkoutMuscleDetailsView: View {
    let summary: WorkoutRecapEngine.Summary
    let unit: MeasurementUnit
    @State private var showsList = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Picker("Muscle display", selection: $showsList) {
                    Text("Muscle map").tag(false)
                    Text("Muscle list").tag(true)
                }.pickerStyle(.segmented).frame(minHeight: 44)
                if !showsList {
                    RecapAnatomy(muscles: summary.muscles).frame(maxWidth: 420).frame(maxWidth: .infinity)
                    RecapMuscleNames(muscles: summary.muscles)
                }
                Text("Trained muscles").font(AppFont.headline)
                ForEach(summary.muscles) { muscle in
                    NavigationLink {
                        WorkoutMuscleContributionsView(muscle: muscle, unit: unit)
                    } label: {
                        RecapCard {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: muscle.role == .primary ? "circle.fill" : "circle.lefthalf.filled")
                                    .foregroundStyle(muscle.role == .primary ? AppColor.trainingPrimaryMuscle : AppColor.trainingSecondaryMuscle)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(muscle.name.capitalized).font(AppFont.headline)
                                    Text("\(muscle.role.rawValue) · \(muscle.setCount) contributing sets")
                                        .font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").accessibilityHidden(true)
                            }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("recap-muscle-\(muscle.id)")
                }
                RecapMissingMapping(count: summary.missingMappings)
                if summary.muscles.isEmpty { Text("No muscle mapping is available for these logged exercises.") }
                RecapCard {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("About muscle mapping").font(AppFont.headline)
                        Text("Highlights are estimated from your logged exercises and completed working sets. They are not a direct measurement of muscle activation.")
                        Text("Warm-ups and unfinished sets are excluded. One set can contribute to several muscles; these counts must not be added to find workout sets.")
                        Text("A muscle can be primary in one exercise and supporting in another. Primary takes precedence on the map; exercise details show both roles. Gray means not highlighted by this mapping, not unused.")
                    }.font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
                }
            }.padding(Spacing.screenPadding)
        }.recapScreen(title: "Muscle details")
    }
}

struct WorkoutMuscleContributionsView: View {
    let muscle: WorkoutRecapEngine.Muscle
    let unit: MeasurementUnit
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("\(muscle.setCount) contributing working sets").font(AppFont.headline)
                ForEach(muscle.contributions) { contribution in
                    RecapCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Text(contribution.name).font(AppFont.headline)
                            Text(contribution.role.rawValue).font(AppFont.subheadline)
                            ForEach(contribution.sets) { set in RecapSetRow(set: set, unit: unit) }
                        }
                    }
                }
            }.padding(Spacing.screenPadding)
        }.recapScreen(title: muscle.name.capitalized)
    }
}

struct WorkoutWeeklyProgressView: View {
    let store: WorkoutRecapStore
    let unit: MeasurementUnit
    var body: some View {
        ScrollView {
            if let week = store.week {
                weeklyContent(week)
            } else if store.historyUnavailable {
                VStack(spacing: Spacing.lg) {
                    Text("Weekly progress is unavailable.")
                    Button("Retry") { Task { await store.load() } }.minimumHitArea()
                }.padding(Spacing.screenPadding)
            } else { ProgressView("Loading weekly progress…").padding(Spacing.screenPadding) }
        }.recapScreen(title: "This week")
            .refreshWorkoutRecap(store)
    }

    private func weeklyContent(_ week: WorkoutRecapEngine.Week) -> some View {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("\(week.count) workouts this week").font(AppFont.title2)
                RecapCard {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        Text("Completed workouts per day").font(AppFont.headline)
                        HStack(alignment: .bottom, spacing: Spacing.sm) {
                            ForEach(week.days) { day in
                                VStack(spacing: Spacing.sm) {
                                    Text(day.count.formatted()).font(AppFont.subheadline).monospacedDigit()
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(day.count > 0 ? AppColor.recapButton : AppColor.recapRaised)
                                        .frame(height: day.count == 0 ? 2 : 100 * CGFloat(day.count) / CGFloat(max(1, week.days.map(\.count).max() ?? 1)))
                                    Text(day.date.formatted(.dateTime.weekday(.narrow))).font(AppFont.subheadline)
                                }.frame(maxWidth: .infinity)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("\(day.date.formatted(.dateTime.weekday(.wide))), \(day.count) workouts")
                            }
                        }
                    }
                }
                if let volume = week.volumeKg {
                    RecapCard {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Recorded volume this week").font(AppFont.headline)
                            Text(RecapFormat.volume(volume, unit: unit)).font(AppFont.title2).monospacedDigit()
                            Text("Supported external-load sets only. More logged volume is not a direct measure of strength.")
                                .font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
                        }
                    }
                }
                Text("Workouts are grouped by their start date in your current calendar and time zone. Finished workouts with working sets and saved manual workouts count. Warm-up-only and unfinished sessions are excluded.")
                    .font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
                if week.count == 0 { Text("No completed workouts this week yet.").font(AppFont.body) }
            }.padding(Spacing.screenPadding)
    }
}

/// Refreshes the current-calendar projection when a visible recap crosses a
/// day/time-zone boundary, or returns from the background. No polling timer.
private struct RecapRefreshModifier: ViewModifier {
    let store: WorkoutRecapStore
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.load() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                Task { await store.load() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                Task { await store.load() }
            }
    }
}

extension View {
    func refreshWorkoutRecap(_ store: WorkoutRecapStore) -> some View {
        modifier(RecapRefreshModifier(store: store))
    }
    func recapScreen(title: String) -> some View {
        background(AppColor.recapBackground.ignoresSafeArea())
            .foregroundStyle(AppColor.recapText).tint(AppColor.recapAction)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
