import SwiftUI

/// The workout screen's picture of the current lift: its start and peak
/// step pictures next to the muscle map when the exercise has a reviewed
/// guide, the muscle map alone otherwise, with the muscle names across the
/// full width underneath. Tapping the pictures opens the exercise page with
/// the cues, the video and the written steps, so form is one tap away
/// mid-set.
struct WorkoutExerciseHero: View {
    let exercise: Exercise?
    let onShowInstructions: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    /// The focus view gives each lift its own hero (`.id`), so this never
    /// carries one exercise's pictures over to the next.
    @State private var images: [CGImage]?
    /// The index lists a clip: the pictures' slot is reserved before they
    /// are cut, so the map doesn't shrink under the user's eyes mid-workout.
    @State private var hasClip = false

    /// Start and peak only: a third picture would squeeze the map.
    private var guide: ExerciseStepGuide.Guide? {
        guard let exercise, let full = ExerciseStepGuide.guide(for: exercise.id, locale: locale),
              let first = full.steps.first, let last = full.steps.last else { return nil }
        return ExerciseStepGuide.Guide(crop: full.crop, steps: full.steps.count > 2 ? [first, last] : full.steps)
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                if let exercise, let guide, hasClip {
                    steps(guide, exercise: exercise)
                        .transition(.opacity)
                }
                ExerciseHeroView(exercise: exercise, showsLegend: false)
            }
            // At accessibility sizes the hero is 120 pt: the legend would leave
            // no room for the figures. VoiceOver reads the names off the map.
            if let exercise, !dynamicTypeSize.isAccessibilitySize {
                ExerciseMuscleLegend(highlights: ExerciseAnatomyEngine.highlights(for: exercise))
            }
        }
        .appAnimation(AppAnimation.fadeIn, value: hasClip)
        .task {
            guard let exercise, !exercise.isCustom, let guide else { return }
            let store = ExerciseClipStore.shared
            let listed = await store.hasClip(for: exercise.id)
            guard !Task.isCancelled else { return }
            hasClip = listed
            guard listed else { return }
            var cut: [CGImage]?
            if let found = await store.clip(for: exercise.id) {
                cut = await ExerciseStepImageStore.shared.images(from: found.url, guide: guide)
            }
            guard !Task.isCancelled else { return }
            images = cut
            // No clip or no pictures: give the map its full width back.
            if cut == nil { hasClip = false }
        }
    }

    private func steps(_ guide: ExerciseStepGuide.Guide, exercise: Exercise) -> some View {
        Button(action: onShowInstructions) {
            ExerciseStepPictures(guide: guide, images: images, showsCues: false)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "info.circle.fill")
                        .font(AppFont.chipText)
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(Spacing.xs)
                        .glassControl(.circle, interactive: false)
                        .padding(Spacing.xs)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("How to do \(exercise.name)"))
        .accessibilityHint(Text("Shows how to perform the exercise"))
    }
}
