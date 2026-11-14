import SwiftUI

/// The top of the exercise page: the interactive body map with the
/// exercise's worked muscles tinted on the same grey figure as everywhere
/// else in the app.
struct ExerciseShowcaseCard: View {
    let exercise: Exercise

    var body: some View {
        GlassCard {
            MuscleActivationMap(exercise: exercise)
        }
    }
}
