import SwiftUI

/// Per-session drill-down from the WorkoutHistoryView list. Shows
/// every logged set, the muscle map for the session, perceived effort,
/// and the note — the full "what happened in this workout" surface so
/// the history list isn't just a roll-up.
struct WorkoutSessionDetailView: View {
    // One-time seed; successful edits explicitly replace the displayed value.
    @State private var session: WorkoutSession
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWorkoutHistorySheet) private var dismissHistorySheet
    @State private var sessionService = WorkoutSessionService.shared

    @State private var confirmingDelete = false
    @State private var namingRoutine = false
    @State private var routineNameDraft = ""
    @State private var savedRoutineName: String?
    @State private var showingActiveWorkoutConflict = false
    @State private var showingEditor = false
    @State private var showingSummary = false

    private var unit: MeasurementUnit { dataStore.profile.bodyMetrics.unit }
    @State private var library = ExerciseLibrary.shared

    init(session: WorkoutSession) {
        _session = State(initialValue: session)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                SessionMuscleCard(session: session)
                statsRow
                if let effort = session.perceivedEffort {
                    perceivedEffortChip(effort)
                }
                if let note = session.note, !note.isEmpty {
                    noteCard(note)
                }
                exercisesList
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.lg)
        }
        .background(AppColor.background.ignoresSafeArea())
        .sheet(isPresented: $showingSummary, onDismiss: {
            if let latest = SwiftDataRepository.shared.loadWorkoutSession(id: session.id) { session = latest }
        }) {
            NavigationStack {
                WorkoutFinishView(session: session, detectedPRs: [], unit: unit, celebratesSave: false) {
                    showingSummary = false
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            WorkoutSavedEditor(session: session, unit: unit) { edited in
                try WorkoutEditValidation.validate(edited, original: session)
                try SwiftDataRepository.shared.saveWorkoutDurably(edited)
                let affected = Set((session.exercises + edited.exercises).map(\.exerciseID))
                session = edited
                dataStore.workoutWasEdited(exerciseIDs: affected)
            }
        }
        .navigationTitle(session.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !session.isActive {
                ToolbarItem(placement: .topBarTrailing) { optionsMenu }
            }
        }
        .confirmationDialog(
            "Delete this workout?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete workout", role: .destructive, action: deleteWorkout)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its sets are removed from your history and personal records are recalculated. This can't be undone.")
        }
        .alert("Save as routine", isPresented: $namingRoutine) {
            TextField("Routine name", text: $routineNameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save", action: saveAsRoutine)
        }
        .alert("Routine saved", isPresented: savedRoutineBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(savedRoutineName ?? "") is ready in Routines.")
        }
        .alert("Workout in progress", isPresented: $showingActiveWorkoutConflict) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Finish or discard your current workout before repeating this one.")
        }
    }

    // MARK: - Actions

    private var optionsMenu: some View {
        Menu {
            Button("View summary", systemImage: "checkmark.circle") { showingSummary = true }
            Button("Edit workout", systemImage: "pencil") { showingEditor = true }
            Button {
                repeatWorkout()
            } label: {
                Label("Repeat workout", systemImage: "arrow.clockwise")
            }
            .disabled(session.exercises.isEmpty)
            Button {
                routineNameDraft = session.name ?? ""
                namingRoutine = true
            } label: {
                Label("Save as routine", systemImage: "square.and.arrow.down")
            }
            .disabled(session.exercises.isEmpty)
            Divider()
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete workout", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(AppFont.scaled(16, weight: .semibold))
        }
        .accessibilityLabel("Workout options")
    }

    private func deleteWorkout() {
        dataStore.deleteWorkout(id: session.id)
        Haptics.success()
        dismiss()
    }

    private func saveAsRoutine() {
        let store = RoutineStore.shared
        // `create` derives the new sort index from the in-memory library,
        // which is empty until some routine surface has loaded it.
        store.load()
        let routine = store.create(
            name: routineNameDraft,
            exercises: Routine(replaying: session, name: routineNameDraft).exercises
        )
        Haptics.success()
        savedRoutineName = routine.name
    }

    /// Starts a fresh session seeded from this one. The Train tab's
    /// container presents the active workout as soon as `activeSession`
    /// appears. Pushed inside a sheet, the whole sheet goes: the workout's
    /// full-screen cover can't present over it.
    private func repeatWorkout() {
        guard sessionService.activeSession == nil else {
            Haptics.warning()
            showingActiveWorkoutConflict = true
            return
        }
        let template = Routine(
            replaying: session,
            name: session.displayName,
            id: session.routineID ?? UUID()
        )
        Haptics.impact(.medium)
        if let dismissHistorySheet {
            dismissHistorySheet()
        } else {
            dismiss()
        }
        sessionService.startWorkout(routine: template, linksRoutine: session.routineID != nil)
    }

    private var savedRoutineBinding: Binding<Bool> {
        Binding(get: { savedRoutineName != nil }, set: { if !$0 { savedRoutineName = nil } })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(dateLabel)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textTertiary)
                .textCase(.uppercase)
            Text(session.displayName)
                .font(AppFont.statHeader)
                .foregroundStyle(AppColor.textPrimary)
        }
    }

    private struct Stat: Hashable {
        let value: String
        let label: String
    }

    private var stats: [Stat] {
        var result = [
            Stat(value: "\(session.exercises.count)", label: String(localized: "Exercises")),
            Stat(value: "\(session.completedSetCount)", label: String(localized: "Sets")),
        ]
        if session.totalVolumeKg > 0 {
            result.append(Stat(value: unit.weightLabel(session.totalVolumeKg), label: String(localized: "Volume")))
        }
        if let durationLabel {
            result.append(Stat(value: durationLabel, label: String(localized: "Duration")))
        }
        return result
    }

    /// One row when every value fits at full size, then two per row, then
    /// one per row, so large text never shrinks or truncates a value.
    private var statsRow: some View {
        let items = stats
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.md) { statTiles(items) }
            Grid(horizontalSpacing: Spacing.md, verticalSpacing: Spacing.md) {
                ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { start in
                    GridRow { statTiles(Array(items[start..<min(start + 2, items.count)])) }
                }
            }
            VStack(spacing: Spacing.md) { statTiles(items) }
        }
    }

    private func statTiles(_ stats: [Stat]) -> some View {
        ForEach(stats, id: \.label) { stat(value: $0.value, label: $0.label) }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value)
                .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.smallCornerRadius)
        .accessibilityElement(children: .combine)
    }

    private func perceivedEffortChip(_ effort: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(AppColor.perceivedEffort)
            Text("Perceived effort")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            Text("\(effort) / 5")
                .font(AppFont.scaled(13, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.smallCornerRadius)
    }

    private func noteCard(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Note")
                .font(AppFont.eyebrow)
                .tracking(1.2)
                .foregroundStyle(AppColor.textTertiary)
            Text(note)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Spacing.smallCornerRadius)
    }

    private var exercisesList: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Exercises")
                .font(AppFont.eyebrow)
                .tracking(1.2)
                .foregroundStyle(AppColor.textSecondary)
            ForEach(session.exercises) { entry in
                exerciseCard(entry: entry)
            }
        }
    }

    private func exerciseCard(entry: WorkoutExerciseEntry) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            let exercise = library.lookup(id: entry.exerciseID)
            exerciseHeader(entry: entry, exercise: exercise)
            Divider().background(AppColor.glassBorder)
            ForEach(entry.sets) { set in
                HStack(spacing: Spacing.sm) {
                    Text("\(set.index)")
                        .font(AppFont.caption2.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 20, alignment: .leading)
                        .foregroundStyle(AppColor.textTertiary)
                        .accessibilityLabel("Set \(set.index)")
                    Text(RecapFormat.set(set, unit: unit))
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textPrimary)
                    if let rpe = set.rpe {
                        Text("RPE \(rpe.formatted(.number.precision(.fractionLength(0...1))))")
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                    if set.isWarmup {
                        Text("W")
                            .font(AppFont.scaled(11, weight: .bold))
                            .foregroundStyle(AppColor.textTertiary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(Capsule().fill(AppColor.surfaceElevated))
                            .accessibilityLabel("Warm-up")
                    } else if set.completed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(AppFont.scaled(13))
                            .foregroundStyle(AppColor.accentPrimary)
                            .accessibilityLabel("Completed")
                    } else {
                        Image(systemName: "circle")
                            .font(AppFont.scaled(13))
                            .foregroundStyle(AppColor.textTertiary)
                            .accessibilityLabel("Not completed")
                    }
                }
                .padding(.vertical, Spacing.xxs)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    /// Opens the exercise's detail when it's still in the library. A
    /// destination link rather than a `TrainNavigation` value, because
    /// this screen is also pushed inside sheets with their own stack.
    @ViewBuilder
    private func exerciseHeader(entry: WorkoutExerciseEntry, exercise: Exercise?) -> some View {
        let label = HStack {
            ExerciseImageView(exercise: exercise)
                .frame(width: 44, height: 44)
            Text(exercise?.name ?? String(localized: "Unknown exercise"))
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer()
            Text("^[\(entry.completedWorkingSets.count) working set](inflect: true)")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
            if exercise != nil {
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        if let exercise {
            NavigationLink {
                ExerciseDetailView(exerciseID: exercise.id)
            } label: { label }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        } else {
            label
        }
    }

    private var dateLabel: String {
        // Use the locale-aware format API instead of a hard-coded
        // `EEEE · MMMM d, yyyy`. Non-Latin locales (ja, zh, ar)
        // render their own canonical week/month strings rather than
        // forcing an English shape onto them (audit Biology L18).
        let date = session.finishedAt ?? session.startedAt
        return date.formatted(
            .dateTime
                .weekday(.wide)
                .month(.wide)
                .day()
                .year()
        )
    }

    private var durationLabel: String? {
        guard session.finishedAt != nil else { return nil }
        return WorkoutRecapEngine.duration(of: session).label
    }
}

// MARK: - Replaying a session as a plan

extension Routine {
    /// A routine that replays a logged session: its exercises in the same
    /// order, each slot sized to the working sets the user actually did.
    /// Weights are left to `RoutineSeedEngine`, which seeds from the
    /// latest history when the routine is started.
    init(replaying session: WorkoutSession, name: String, id: UUID = UUID()) {
        let slots = session.exercises
            .sorted { $0.index < $1.index }
            .enumerated()
            .map { position, entry in RoutineExercise(replaying: entry, index: position) }
        self.init(id: id, name: name, exercises: slots)
    }
}

extension RoutineExercise {
    /// Reps a slot targets when the logged sets carry none.
    static let fallbackTargetReps = 10

    /// Completed working sets when there are any, otherwise every working
    /// set — a session abandoned before any check-off still describes the
    /// plan the user meant to follow. Warm-ups never count.
    init(replaying entry: WorkoutExerciseEntry, index: Int) {
        let working = entry.sets.filter { !$0.isWarmup }
        let completed = working.filter(\.completed)
        let basis = completed.isEmpty ? working : completed
        let reps = basis.first(where: { $0.supportsRepLogging && $0.reps > 0 })?.reps ?? Self.fallbackTargetReps
        self.init(
            exerciseID: entry.exerciseID,
            index: index,
            targetSets: Self.clamped(basis.count, to: RoutineEditEngine.targetSets),
            targetReps: Self.clamped(reps, to: RoutineEditEngine.targetReps),
            restSeconds: entry.restSeconds,
            note: entry.note,
            supersetGroup: entry.supersetGroup
        )
    }

    private static func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

extension EnvironmentValues {
    /// Dismisses the sheet a workout detail was pushed inside, set by
    /// `MuscleHistorySheet`. Nil when the detail lives in the Train stack.
    @Entry var dismissWorkoutHistorySheet: (() -> Void)? = nil
}
