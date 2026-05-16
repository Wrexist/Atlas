import SwiftUI

/// Single exercise row used by the library list and (in later
/// commits) the routine editor's exercise picker. Renders a 56×56
/// image tile, the name, primary-muscle pills, and a chevron when
/// `showsChevron` is on.
struct ExerciseRow: View {
    let exercise: Exercise
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: Spacing.md) {
            ExerciseImageView(
                imagePath: exercise.images.first,
                muscleGroup: exercise.muscleGroup
            )
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(exercise.name)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: Spacing.xs) {
                    musclePill
                    equipmentPill
                }
                .lineLimit(1)
            }

            Spacer(minLength: Spacing.xs)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary.opacity(0.6))
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
    }

    private var musclePill: some View {
        Text(exercise.muscleGroup.displayName)
            .font(AppFont.chipText)
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(AppColor.surfaceSecondary.opacity(0.6))
            )
    }

    @ViewBuilder
    private var equipmentPill: some View {
        if exercise.equipmentKind != .bodyweight {
            HStack(spacing: 3) {
                Image(systemName: exercise.equipmentKind.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                Text(exercise.equipmentKind.displayName)
                    .font(AppFont.chipText)
            }
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(
                Capsule().stroke(AppColor.glassBorder, lineWidth: 0.5)
            )
        }
    }
}
