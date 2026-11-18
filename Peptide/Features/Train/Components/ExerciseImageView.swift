import SwiftUI

/// The exercise tile on picker rows, routines, workout strips and recaps:
/// the middle step picture when the exercise has one, otherwise the Atlas
/// body zoomed to the muscles it works, with an equipment badge.
struct ExerciseImageView: View {
    let exercise: Exercise?
    var cornerRadius: CGFloat = Spacing.smallCornerRadius

    var body: some View {
        Group {
            if let exercise, let step = ExerciseStepArt.thumbnailName(for: exercise.id) {
                Image(step)
                    .resizable()
                    .scaledToFit()
                    .padding(Spacing.xxs)
            } else if let exercise {
                ExerciseMuscleThumbnail(highlights: ExerciseAnatomyEngine.highlights(for: exercise))
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background)
        .overlay(alignment: .bottomTrailing) {
            if let exercise {
                GlyphImage(glyph: exercise.equipmentKind.glyph)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(3)
                    .background(AppColor.surfaceElevated, in: Circle())
                    .padding(2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
