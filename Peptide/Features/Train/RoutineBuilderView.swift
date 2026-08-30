import SwiftUI

/// The routine editor: name it, stack exercises into it, set what you're
/// aiming for on each, and start it.
///
/// State lives in `RoutineStore` rather than a local copy — the list
/// behind this screen renders the same routine, and two copies of a
/// mutable draft is how a rename ends up showing on one screen and not
/// the other. Every edit is a `RoutineEditEngine` transform written
/// straight back through the store.
struct RoutineBuilderView: View {
    let routineID: UUID

    @State private var store = RoutineStore.shared
    @State private var library = ExerciseLibrary.shared
    @State private var addingExercise = false
    @State private var editingTargets: RoutineExercise?
    @State private var renaming = false
    @State private var nameDraft = ""
    @Environment(\.dismiss) private var dismiss

    private var routine: Routine? { store.routines.first { $0.id == routineID } }

    var body: some View {
        Group {
            if let routine {
                editor(routine)
            } else {
                // Deleted from the list behind us, or opened from a stale
                // deep link. An empty state beats a blank editor bound to
                // nothing.
                EmptyStateView(
                    icon: "questionmark.circle",
                    title: "Routine not found",
                    message: "This routine may have been deleted.",
                    action: .init(title: "Back to routines") { dismiss() }
                )
                .padding(Spacing.screenPadding)
            }
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle(routine?.name ?? "Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let routine, !routine.exercises.isEmpty {
                // Reorder and delete come from the system's edit mode
                // rather than always-on drag handles, which would sit
                // under the target pill on every row.
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
            if routine != nil {
                ToolbarItem(placement: .topBarTrailing) { overflowMenu }
            }
        }
        .task { await library.load() }
        .sheet(isPresented: $addingExercise) {
            ExercisePickerSheet { exercise in
                add(exercise)
            }
        }
        .sheet(item: $editingTargets) { slot in
            RoutineTargetSheet(
                exerciseName: name(of: slot.exerciseID),
                sets: slot.targetSets,
                reps: slot.targetReps
            ) { sets, reps in
                updateTargets(slotID: slot.id, sets: sets, reps: reps)
            }
        }
        .alert("Rename routine", isPresented: $renaming) {
            TextField("Routine name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { store.rename(id: routineID, to: nameDraft) }
        }
    }

    // MARK: - Editor

    private func editor(_ routine: Routine) -> some View {
        VStack(spacing: 0) {
            header(routine)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.md)

            if routine.exercises.isEmpty {
                emptyState
            } else {
                slotList(routine)
            }
        }
        .padding(.top, Spacing.md)
    }

    private func header(_ routine: Routine) -> some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.lg) {
                stat("\(routine.exercises.count)", label: "Exercises")
                stat("\(RoutineSeedEngine.totalSets(in: routine))", label: "Sets")
                stat("~\(RoutineSeedEngine.estimatedMinutes(for: routine))", label: "Minutes")
            }
            .frame(maxWidth: .infinity)

            PrimaryCTAButton(title: "Start workout", icon: "play.fill", shape: .rounded) {
                Haptics.impact(.medium)
                store.startWorkout(from: routine)
            }
            .disabled(routine.exercises.isEmpty)
            .opacity(routine.exercises.isEmpty ? 0.5 : 1)
        }
    }

    private func stat(_ value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text(value)
                .font(AppFont.scaled(24, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(AppFont.scaled(11, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func slotList(_ routine: Routine) -> some View {
        List {
            ForEach(routine.exercises.sorted { $0.index < $1.index }) { slot in
                RoutineSlotRow(
                    name: name(of: slot.exerciseID),
                    detail: detail(of: slot.exerciseID),
                    sets: slot.targetSets,
                    reps: slot.targetReps,
                    onEditTargets: { editingTargets = slot }
                )
                .listRowInsets(EdgeInsets(
                    top: Spacing.xxs,
                    leading: Spacing.screenPadding,
                    bottom: Spacing.xxs,
                    trailing: Spacing.screenPadding
                ))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .onMove { source, destination in
                store.save(RoutineEditEngine.movingSlots(
                    in: routine, fromOffsets: source, toOffset: destination
                ))
            }
            .onDelete { offsets in
                remove(at: offsets, in: routine)
            }

            addExerciseButton
                .listRowInsets(EdgeInsets(
                    top: Spacing.sm,
                    leading: Spacing.screenPadding,
                    bottom: Spacing.xxxl,
                    trailing: Spacing.screenPadding
                ))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private var addExerciseButton: some View {
        GlassButton(title: "Add exercise", icon: "plus", style: .secondary, isFullWidth: true) {
            addingExercise = true
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            EmptyStateView(
                icon: "figure.strengthtraining.traditional",
                title: "Add your first exercise",
                message: "Pick the lifts you want in this session and set what you're aiming for. You can reorder them any time.",
                action: .init(title: "Add exercise", icon: "plus") { addingExercise = true }
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.screenPadding)
    }

    private var overflowMenu: some View {
        Menu {
            Button {
                nameDraft = routine?.name ?? ""
                renaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                addingExercise = true
            } label: {
                Label("Add exercise", systemImage: "plus")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(AppFont.scaled(16, weight: .semibold))
        }
        .accessibilityLabel("Routine options")
    }

    // MARK: - Edits

    private func add(_ exercise: Exercise) {
        guard let routine else { return }
        Haptics.selection()
        store.save(RoutineEditEngine.appending(exerciseID: exercise.id, to: routine))
    }

    private func remove(at offsets: IndexSet, in routine: Routine) {
        let ordered = routine.exercises.sorted { $0.index < $1.index }
        var updated = routine
        for index in offsets {
            guard ordered.indices.contains(index) else { continue }
            updated = RoutineEditEngine.removingSlot(id: ordered[index].id, from: updated)
        }
        store.save(updated)
    }

    private func updateTargets(slotID: UUID, sets: Int, reps: Int) {
        guard let routine else { return }
        store.save(RoutineEditEngine.updatingTargets(
            slotID: slotID, sets: sets, reps: reps, in: routine
        ))
    }

    // MARK: - Library lookups

    private func name(of exerciseID: String) -> String {
        library.lookup(id: exerciseID)?.name ?? "Unknown exercise"
    }

    private func detail(of exerciseID: String) -> String {
        guard let exercise = library.lookup(id: exerciseID) else { return "Not in your library" }
        let equipment = exercise.equipment?.capitalized
        return [exercise.muscleGroup.displayName, equipment]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

// MARK: - Slot row

/// One exercise slot. The trailing "5 × 5" pill is the target editor's
/// entry point — a full-width tap target for the row itself would fight
/// the drag handle that edit mode puts on every row here.
private struct RoutineSlotRow: View {
    let name: String
    let detail: String
    let sets: Int
    let reps: Int
    let onEditTargets: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(name)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            Button(action: onEditTargets) {
                Text("\(sets) × \(reps)")
                    .font(AppFont.scaled(13, weight: .bold))
                    .foregroundStyle(AppColor.accentLight)
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: Spacing.minimumHitTarget)
                    .background(Capsule().fill(AppColor.accentPrimary.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name) target: \(sets) sets of \(reps) reps")
            .accessibilityHint("Opens the set and rep picker")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .insetRowBackground()
    }
}

// MARK: - Target sheet

/// Sets × reps for one slot. A sheet rather than two inline steppers:
/// steppers on every row turn a six-exercise routine into twelve tiny
/// targets stacked beside a drag handle.
private struct RoutineTargetSheet: View {
    let exerciseName: String
    @State private var sets: Int
    @State private var reps: Int
    let onSave: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    init(exerciseName: String, sets: Int, reps: Int, onSave: @escaping (Int, Int) -> Void) {
        self.exerciseName = exerciseName
        self._sets = State(initialValue: sets)
        self._reps = State(initialValue: reps)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                GlassCard {
                    VStack(spacing: Spacing.lg) {
                        Stepper(value: $sets, in: RoutineEditEngine.targetSets) {
                            field("Sets", value: "\(sets)")
                        }
                        Divider().background(AppColor.glassBorder)
                        Stepper(value: $reps, in: RoutineEditEngine.targetReps) {
                            field("Reps", value: "\(reps)")
                        }
                    }
                }

                Text("Starting this routine seeds \(sets) empty sets, each aiming for \(reps) reps at the weight you last lifted.")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(Spacing.screenPadding)
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onSave(sets, reps)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .liquidGlassPresentation(detents: [.medium])
    }

    private func field(_ label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: 0)
            Text(value)
                .font(AppFont.scaled(24, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.accentLight)
                .contentTransition(.numericText())
        }
    }
}

#Preview("Routine builder") {
    NavigationStack {
        RoutineBuilderView(routineID: UUID())
    }
    .preferredColorScheme(.dark)
}
