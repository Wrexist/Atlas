import SwiftUI

/// The workout screen's picture of the current lift: the muscle map, with
/// the muscle names across the full width underneath.
struct WorkoutExerciseHero: View {
    let exercise: Exercise?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ExerciseHeroView(exercise: exercise, showsLegend: false)
            // At accessibility sizes the hero is 120 pt: the legend would leave
            // no room for the figures. VoiceOver reads the names off the map.
            if let exercise, !dynamicTypeSize.isAccessibilitySize {
                ExerciseMuscleLegend(highlights: ExerciseAnatomyEngine.highlights(for: exercise))
            }
        }
    }
}
