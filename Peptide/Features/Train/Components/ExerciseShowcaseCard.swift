import SwiftUI

/// The top of the exercise page: the step pictures when the exercise has
/// them, then the interactive body map with the exercise's worked muscles
/// tinted on the same grey figure as everywhere else in the app.
struct ExerciseShowcaseCard: View {
    let exercise: Exercise

    var body: some View {
        let steps = ExerciseStepArt.assetNames(for: exercise.id)
        GlassCard {
            VStack(spacing: Spacing.lg) {
                if !steps.isEmpty {
                    ExerciseStepStrip(assetNames: steps, height: 170)
                }
                MuscleActivationMap(exercise: exercise)
            }
        }
    }
}
