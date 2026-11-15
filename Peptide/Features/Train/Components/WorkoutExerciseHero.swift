import SwiftUI

/// The workout screen's picture of the current lift: the step pictures when
/// the exercise has them, otherwise the muscle map with the muscle names
/// across the full width underneath.
struct WorkoutExerciseHero: View {
    let exercise: Exercise?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let steps = exercise.map { ExerciseStepArt.assetNames(for: $0.id) } ?? []
        VStack(spacing: Spacing.sm) {
            if steps.isEmpty {
                ExerciseHeroView(exercise: exercise, showsLegend: false)
            } else {
                ExerciseStepStrip(assetNames: steps, height: dynamicTypeSize.isAccessibilitySize ? 110 : 150)
            }
            // At accessibility sizes the hero is 120 pt: the legend would leave
            // no room for the figures. VoiceOver reads the names off the map.
            if let exercise, !dynamicTypeSize.isAccessibilitySize {
                ExerciseMuscleLegend(highlights: ExerciseAnatomyEngine.highlights(for: exercise))
            }
        }
    }
}
