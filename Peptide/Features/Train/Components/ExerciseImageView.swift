import SwiftUI

/// The exercise tile on picker rows, routines, workout strips and recaps:
/// the Atlas body zoomed to the muscles the exercise works, with an
/// equipment badge. Catalog and custom exercises render alike.
struct ExerciseImageView: View {
    let exercise: Exercise?
    var cornerRadius: CGFloat = Spacing.smallCornerRadius

    var body: some View {
        Group {
            if let exercise {
                ExerciseMuscleThumbnail(highlights: ExerciseAnatomyEngine.highlights(for: exercise))
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.trainingBackground)
        .overlay(alignment: .bottomTrailing) {
            if let exercise {
                Image(systemName: exercise.equipmentKind.symbolName)
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(3)
                    .background(AppColor.trainingPanel, in: Circle())
                    .padding(2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
