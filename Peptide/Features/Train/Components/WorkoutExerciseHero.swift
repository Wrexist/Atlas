import SwiftUI

/// The workout screen's picture of the current lift: the movement looping
/// next to the muscle map when a clip exists, the muscle map alone
/// otherwise, with the muscle names across the full width underneath.
/// Tapping the movement opens the exercise page with its step-by-step
/// instructions, so form is one tap away mid-set.
struct WorkoutExerciseHero: View {
    let exercise: Exercise?
    /// False while the instructions sheet covers the screen: the sheet plays
    /// its own copy, so this one pauses.
    let isVisible: Bool
    let onShowInstructions: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The focus view gives each lift its own hero (`.id`), so this never
    /// carries one exercise's clip over to the next.
    @State private var clip: ExerciseClipStore.Clip?
    /// The index lists a clip: its slot is reserved before the video is in,
    /// so the map doesn't shrink under the user's eyes mid-workout.
    @State private var hasClip = false

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                if let exercise, hasClip {
                    movementSlot(exercise)
                        .transition(.opacity)
                }
                ExerciseHeroView(exercise: exercise, showsLegend: false)
            }
            if let exercise {
                ExerciseMuscleLegend(highlights: ExerciseAnatomyEngine.highlights(for: exercise))
            }
        }
        .appAnimation(AppAnimation.fadeIn, value: clip)
        .appAnimation(AppAnimation.fadeIn, value: hasClip)
        .task {
            guard let exercise, !exercise.isCustom else { return }
            let store = ExerciseClipStore.shared
            let listed = await store.hasClip(for: exercise.id)
            guard !Task.isCancelled, listed else { return }
            hasClip = true
            let found = await store.clip(for: exercise.id)
            guard !Task.isCancelled else { return }
            clip = found
            // The download failed: give the map its full width back.
            if found == nil { hasClip = false }
        }
    }

    @ViewBuilder
    private func movementSlot(_ exercise: Exercise) -> some View {
        if let clip {
            movement(clip, exercise: exercise)
        } else {
            RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous)
                .fill(AppColor.track)
                .aspectRatio(4 / 5, contentMode: .fit)
                .shimmer()
                .accessibilityElement()
                .accessibilityLabel(Text("Loading animation"))
        }
    }

    private func movement(_ clip: ExerciseClipStore.Clip, exercise: Exercise) -> some View {
        Button(action: onShowInstructions) {
            LoopingVideo(url: clip.url, isTransparent: clip.isTransparent, playing: isVisible && !reduceMotion)
                .id(clip.url)
                .allowsHitTesting(false)
                .aspectRatio(4 / 5, contentMode: .fit)
                .clipShape(RoundedRectangle(
                    cornerRadius: clip.isTransparent ? 0 : Spacing.controlCornerRadius, style: .continuous
                ))
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
        .accessibilityLabel(Text("Animation of \(exercise.name)"))
        .accessibilityHint(Text("Shows how to perform the exercise"))
    }
}
