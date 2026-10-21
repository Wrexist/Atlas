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
                exercise: exercise
            )
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(exercise.name)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.xs) { musclePill; equipmentPill }
                    VStack(alignment: .leading, spacing: Spacing.xs) { musclePill; equipmentPill }
                }
            }

            Spacer(minLength: Spacing.xs)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary.opacity(0.6))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        // One VoiceOver stop per exercise, not four — the tile, the name,
        // the two pills and the chevron are one piece of information.
        .accessibilityElement(children: .combine)
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
                GlyphImage(glyph: exercise.equipmentKind.glyph)
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

/// Loading stand-in shaped like `ExerciseRow`, so the list doesn't jump
/// when the library finishes parsing.
struct ExerciseRowSkeletonList: View {
    var rowCount = 8

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { _ in
                HStack(spacing: Spacing.md) {
                    SkeletonBlock(width: 56, height: 56, cornerRadius: Spacing.smallCornerRadius)
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        SkeletonBlock(width: 180, height: 14)
                        SkeletonBlock(width: 90, height: 12)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Spacing.xs)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.xxs)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading exercises")
    }
}
