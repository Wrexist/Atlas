import SwiftUI

/// Per-session drill-down from the WorkoutHistoryView list. Shows
/// every logged set, the muscle map for the session, any PRs the
/// engine detected at the time, perceived effort, and the note —
/// the full "what happened in this workout" surface so the history
/// list isn't just a roll-up.
///
/// Pulls PRs from `PRDetectionEngine.recordedPRs(for:)` rather than
/// re-running ingest (which would mutate the records and return
/// empty on re-open — same bug we fixed in WorkoutFinishView).
struct WorkoutSessionDetailView: View {
    let session: WorkoutSession
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    @State private var sessionService = WorkoutSessionService.shared

    @State private var confirmingDelete = false
    @State private var namingRoutine = false
    @State private var routineNameDraft = ""
    @State private var savedRoutineName: String?
    @State private var showingActiveWorkoutConflict = false

    private var unit: MeasurementUnit { dataStore.profile.bodyMetrics.unit }
    @State private var library = ExerciseLibrary.shared

    private var muscleHighlights: [AnatomicalMuscle: MuscleHighlight] {
        let exercises = session.exercises.compactMap { library.lookup(id: $0.exerciseID) }
        return MuscleMapView.highlights(forExercises: exercises)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                MuscleMapView(highlights: muscleHighlights)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 320)
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
        .navigationTitle(session.name ?? "Workout")
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
    /// appears, so popping back here is all the hand-off needed.
    private func repeatWorkout() {
        guard sessionService.activeSession == nil else {
            Haptics.warning()
            showingActiveWorkoutConflict = true
            return
        }
        let template = Routine(
            replaying: session,
            name: session.name ?? String(localized: "Workout"),
            id: session.routineID ?? UUID()
        )
        Haptics.impact(.medium)
        sessionService.startWorkout(routine: template)
        dismiss()
    }

    private var savedRoutineBinding: Binding<Bool> {
        Binding(get: { savedRoutineName != nil }, set: { if !$0 { savedRoutineName = nil } })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateLabel)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .textCase(.uppercase)
            Text(session.name ?? "Workout")
                .font(AppFont.statHeader)
                .foregroundStyle(AppColor.textPrimary)
        }
    }

    private var statsRow: some View {
        HStack(spacing: Spacing.md) {
            stat(value: "\(session.exercises.count)", label: "Exercises")
            stat(value: "\(session.completedSetCount)", label: "Sets")
            if let durationLabel {
                stat(value: durationLabel, label: "Duration")
            }
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .stroke(AppColor.glassBorder, lineWidth: 0.5)
        )
    }

    private func perceivedEffortChip(_ effort: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(AppColor.perceivedEffort)
            Text("Perceived effort")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            Text("\(effort) / 5")
                .font(AppFont.scaled(13, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
    }

    private func noteCard(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
        .background(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
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
            HStack {
                Text(exercise?.name ?? entry.exerciseID)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text("\(entry.sets.filter(\.completed).count) sets")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Divider().background(AppColor.glassBorder)
            ForEach(entry.sets) { set in
                HStack(spacing: Spacing.sm) {
                    Text("\(set.index)")
                        .font(AppFont.caption.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 20, alignment: .leading)
                        .foregroundStyle(AppColor.textTertiary)
                    if set.weightKg > 0 {
                        Text("\(unit.weightLabel(set.weightKg, fractionDigits: 1)) × \(set.reps)")
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textPrimary)
                    } else {
                        Text("\(set.reps) reps")
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    if let rpe = set.rpe {
                        Text("RPE \(rpe, specifier: "%.1f")")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                    if set.isWarmup {
                        Text("W")
                            .font(AppFont.scaled(11, weight: .bold))
                            .foregroundStyle(AppColor.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppColor.surfaceElevated))
                    } else if set.completed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(AppFont.scaled(13))
                            .foregroundStyle(AppColor.accentPrimary)
                    } else {
                        Image(systemName: "circle")
                            .font(AppFont.scaled(13))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .stroke(AppColor.glassBorder, lineWidth: 0.5)
        )
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
        guard let finished = session.finishedAt else { return nil }
        let interval = finished.timeIntervalSince(session.startedAt)
        guard interval > 0 else { return nil }
        let totalMinutes = Int(interval / 60)
        if totalMinutes < 60 { return "\(totalMinutes)m" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
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
        let reps = basis.first(where: { $0.reps > 0 })?.reps ?? Self.fallbackTargetReps
        self.init(
            exerciseID: entry.exerciseID,
            index: index,
            targetSets: Self.clamped(basis.count, to: RoutineEditEngine.targetSets),
            targetReps: Self.clamped(reps, to: RoutineEditEngine.targetReps),
            restSeconds: entry.restSeconds,
            note: entry.note
        )
    }

    private static func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
