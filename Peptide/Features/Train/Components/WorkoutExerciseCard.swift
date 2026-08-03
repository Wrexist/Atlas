import SwiftUI

/// One exercise's worth of sets inside the active-workout screen.
/// Header shows the exercise thumbnail + name + a context menu;
/// table of `SetEditorRow`s; "Add set" CTA at the bottom.
struct WorkoutExerciseCard: View {
    let entry: WorkoutExerciseEntry
    let exercise: Exercise?
    /// Looks up the user's last completed set for this exercise from
    /// past sessions — wired to PRDetectionEngine's stored records.
    /// `nil` means there's no prior session and the "60 × 8" cue
    /// row renders as "—". Was previously hard-coded `nil` in this
    /// view, which silently dropped the entire "log a set with last-
    /// weight inline" UX promise (audit Train C1).
    let unit: MeasurementUnit
    let previousSetLookup: () -> SetEntry?
    let onSetUpdate: (SetEntry) -> Void
    let onAddSet: () -> Void
    let onRemoveSet: (UUID) -> Void
    let onRemoveExercise: () -> Void

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
                Text(exercise?.name ?? entry.exerciseID)
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
                Button(role: .destructive, action: onRemoveExercise) {
                    Label("Remove exercise", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(Spacing.xs)
            }
            .accessibilityLabel("Exercise options")
        }
    }

    private var setsList: some View {
        // Compute once per render so every row in this exercise card
        // shares the same prior-session reference (the lookup hits
        // SwiftData and shouldn't run N times for N sets).
        let lastSession = previousSetLookup()
        return VStack(spacing: 0) {
            ForEach(entry.sets) { setSnapshot in
                SetEditorRow(
                    set: Binding(
                        get: { setSnapshot },
                        set: { onSetUpdate($0) }
                    ),
                    previousSet: lastSession,
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
