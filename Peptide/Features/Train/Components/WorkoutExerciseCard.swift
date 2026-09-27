import SwiftUI

/// One exercise's worth of sets inside the active-workout screen.
/// Header shows the exercise thumbnail + name + a context menu;
/// table of `SetEditorRow`s; "Add set" CTA at the bottom.
struct WorkoutExerciseCard: View {
    let entry: WorkoutExerciseEntry
    let exercise: Exercise?
    let unit: MeasurementUnit
    /// The completed sets from the last session that logged this
    /// exercise. Each row's "60 × 8" cue is paired to one of them by
    /// `PreviousSetEngine`; empty means no history and the cue reads "—".
    let previousSetsLookup: () -> [SetEntry]
    /// Rest the timer will use after a set here — the entry's own
    /// override or the user's default — so the menu can tick it.
    let effectiveRestSeconds: Int
    let onSetUpdate: (SetEntry) -> Void
    let onAddSet: () -> Void
    let onRemoveSet: (UUID) -> Void
    let onRemoveExercise: () -> Void
    let onSetRestSeconds: (Int) -> Void

    @State private var confirmingRemoval = false

    private var completedSetCount: Int { entry.sets.filter(\.completed).count }

    private var displayName: String { exercise?.name ?? entry.exerciseID }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header
                Divider().background(AppColor.glassBorder)
                setsList
                addSetButton
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            ExerciseImageView(
                imagePath: exercise?.images.first,
                muscleGroup: exercise?.muscleGroup ?? .fullBody
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                if let exercise {
                    Text(exercise.muscleGroup.displayName)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            Spacer()

            Menu {
                restMenu
                Button(role: .destructive, action: requestRemoval) {
                    Label("Remove exercise", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(Spacing.xs)
                    .minimumHitArea()
            }
            .accessibilityLabel("Exercise options")
        }
        .confirmationDialog(
            "Remove \(displayName)?",
            isPresented: $confirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove exercise", role: .destructive, action: onRemoveExercise)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removalMessage)
        }
    }

    private var removalMessage: String {
        completedSetCount == 1
            ? "Your completed set will be deleted."
            : "Your \(completedSetCount) completed sets will be deleted."
    }

    private var restMenu: some View {
        Menu {
            ForEach(RestTimeOptions.choices(including: effectiveRestSeconds), id: \.self) { seconds in
                Button {
                    onSetRestSeconds(seconds)
                } label: {
                    if seconds == effectiveRestSeconds {
                        Label(RestTimeOptions.label(for: seconds), systemImage: "checkmark")
                    } else {
                        Text(RestTimeOptions.label(for: seconds))
                    }
                }
            }
        } label: {
            Label("Rest time · \(RestTimeOptions.label(for: effectiveRestSeconds))", systemImage: "timer")
        }
    }

    /// Logged work is only lost behind a confirmation; an exercise with
    /// nothing checked off goes straight away.
    private func requestRemoval() {
        if completedSetCount > 0 {
            confirmingRemoval = true
        } else {
            onRemoveExercise()
        }
    }

    private var setsList: some View {
        // Resolved once per render, not per row.
        let hints = PreviousSetEngine.hints(for: entry.sets, previous: previousSetsLookup())
        return VStack(spacing: 0) {
            ForEach(entry.sets) { setSnapshot in
                SetEditorRow(
                    set: Binding(
                        get: { setSnapshot },
                        set: { onSetUpdate($0) }
                    ),
                    previousSet: hints[setSnapshot.id],
                    unit: unit,
                    onDelete: { onRemoveSet(setSnapshot.id) }
                )
                if setSnapshot.id != entry.sets.last?.id {
                    Divider()
                        .background(AppColor.glassBorder.opacity(0.5))
                        .padding(.leading, Spacing.xl + Spacing.sm)
                }
            }
        }
    }

    private var addSetButton: some View {
        Button(action: onAddSet) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text("Add set")
            }
            .font(AppFont.callout.weight(.semibold))
            .foregroundStyle(AppColor.accentPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.accentPrimary.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }
}
