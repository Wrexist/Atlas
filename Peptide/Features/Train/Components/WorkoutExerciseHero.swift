import SwiftUI

/// The workout screen's picture of the current lift: the movement looping
/// next to the muscle map when a clip exists, the muscle map alone
/// otherwise. Tapping the movement opens the exercise page with its
/// step-by-step instructions, so form is one tap away mid-set.
struct WorkoutExerciseHero: View {
    let exercise: Exercise?
    let onShowInstructions: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The focus view gives each lift its own hero (`.id`), so this never
    /// carries one exercise's clip over to the next.
    @State private var clip: ExerciseClipStore.Clip?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let clip, let exercise {
                movement(clip, exercise: exercise)
                    .transition(.opacity)
            }
            ExerciseHeroView(exercise: exercise)
        }
        .appAnimation(AppAnimation.fadeIn, value: clip)
        .task {
            guard let exercise, !exercise.isCustom else { return }
            clip = await ExerciseClipStore.shared.clip(for: exercise.id)
        }
    }

    private func movement(_ clip: ExerciseClipStore.Clip, exercise: Exercise) -> some View {
        Button(action: onShowInstructions) {
            LoopingVideo(url: clip.url, isTransparent: clip.isTransparent, playing: !reduceMotion)
                .id(clip.url)
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
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(Text("Animation of \(exercise.name)"))
        .accessibilityHint(Text("Shows how to perform the exercise"))
    }
}
