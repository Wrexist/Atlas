import SwiftUI

/// How an exercise is performed: its start and finish positions, with the
/// trained muscles inset so form and target read together. The positions
/// alternate like a two-frame loop; with Reduce Motion they sit side by side.
struct ExerciseMovementView: View {
    let exercise: Exercise
    let photos: ExercisePhotos.Pair

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsFinish = false

    private static let holdDuration: Duration = .milliseconds(1400)

    var body: some View {
        Group {
            if reduceMotion { sideBySide } else { alternating }
        }
        .overlay(alignment: .bottomTrailing) { muscleInset }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(exercise.name): start and finish positions. Primary: \(exercise.primaryMuscles.joined(separator: ", ")). Supporting: \(exercise.secondaryMuscles.joined(separator: ", "))."))
    }

    private var alternating: some View {
        photo(photos.start)
            .overlay { photo(photos.finish).opacity(showsFinish ? 1 : 0) }
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
            .overlay(alignment: .topLeading) {
                phaseLabel(showsFinish ? "Finish" : "Start", step: showsFinish ? 2 : 1)
                    .contentTransition(.opacity)
                    .padding(Spacing.sm)
            }
            .task { await alternate() }
    }

    private var sideBySide: some View {
        HStack(spacing: Spacing.xs) {
            labeledPhoto(photos.start, title: "Start", step: 1)
            labeledPhoto(photos.finish, title: "Finish", step: 2)
        }
    }

    private func labeledPhoto(_ image: UIImage, title: String, step: Int) -> some View {
        photo(image)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous))
            .overlay(alignment: .topLeading) { phaseLabel(title, step: step).padding(Spacing.xs) }
    }

    private func photo(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
    }

    private func phaseLabel(_ title: String, step: Int) -> some View {
        HStack(spacing: Spacing.xs) {
            Text("\(step)")
                .font(AppFont.badge)
                .monospacedDigit()
            Text(title)
                .font(AppFont.footnote.weight(.semibold))
        }
        .foregroundStyle(AppColor.textPrimary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .glassControl(.capsule, interactive: false)
    }

    private var muscleInset: some View {
        ExerciseMuscleMap(exercise: exercise, orientation: ExerciseMuscleMap.preferredOrientation(for: exercise))
            .padding(Spacing.xs)
            .frame(width: 64, height: 88)
            .glassControl(.rect(cornerRadius: Spacing.smallCornerRadius), interactive: false)
            .padding(Spacing.sm)
    }

    /// Runs only while on screen: `.task` cancels when the view disappears.
    private func alternate() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.holdDuration)
            guard !Task.isCancelled else { return }
            AppAnimation.with(AppAnimation.settle) { showsFinish.toggle() }
        }
    }
}
