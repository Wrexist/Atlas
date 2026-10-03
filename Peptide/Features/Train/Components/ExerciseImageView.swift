import SwiftUI

/// The same offline illustration on picker rows, routines and workout strips.
/// Resolve by exercise identity, never by a similar name or an upstream photo.
struct ExerciseImageView: View {
    let exercise: Exercise?
    var cornerRadius: CGFloat = Spacing.smallCornerRadius

    var body: some View {
        ExerciseHeroView(exercise: exercise, compact: true)
            .padding(Spacing.xs)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.trainingBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}
