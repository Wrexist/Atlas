import SwiftUI

/// One exercise's worth of sets inside the active-workout screen.
/// Header shows the exercise thumbnail + name + a context menu;
/// table of `SetEditorRow`s; "Add set" CTA at the bottom.
struct WorkoutExerciseCard: View {
    let entry: WorkoutExerciseEntry
    let exercise: Exercise?
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(Spacing.xs)
            }
            .accessibilityLabel("Exercise options")
        }
    }

    private var setsList: some View {
        VStack(spacing: 0) {
            ForEach(entry.sets) { setSnapshot in
                SetEditorRow(
                    set: Binding(
                        get: { setSnapshot },
                        set: { onSetUpdate($0) }
                    ),
                    previousSet: nil,
                    onDelete: { onRemoveSet(setSnapshot.id) }
                )
                if setSnapshot.id != entry.sets.last?.id {
                    Divider()
                        .background(AppColor.glassBorder.opacity(0.5))
                        .padding(.leading, 30)
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
