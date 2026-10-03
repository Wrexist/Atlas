import SwiftUI

struct ExerciseHeroView: View {
    let exercise: Exercise?
    var compact = false

    var body: some View {
        Group {
            if let exercise, let asset = ExerciseVisualAssets.poster(for: exercise.id) {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(Text("\(exercise.name) illustration"))
            } else if let exercise {
                MuscleMapView(
                    highlights: MuscleMapView.highlights(for: exercise),
                    orientation: compact ? preferredOrientation(exercise) : .both,
                    primaryColor: AppColor.trainingPrimaryMuscle,
                    secondaryColor: AppColor.trainingSecondaryMuscle,
                    silhouetteFill: AppColor.textSecondary.opacity(0.10),
                    silhouetteStroke: AppColor.textSecondary.opacity(0.30),
                    showsSkeleton: false,
                    muscleBaseline: AppColor.textSecondary.opacity(0.20),
                    tendonStroke: AppColor.textSecondary.opacity(0.25),
                    identifiesOnTap: false
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Muscle map for \(exercise.name). Primary: \(exercise.primaryMuscles.joined(separator: ", ")). Secondary: \(exercise.secondaryMuscles.joined(separator: ", "))."))
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(AppFont.statValue)
                    .foregroundStyle(AppColor.textSecondary)
                    .accessibilityLabel("Exercise illustration unavailable")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func preferredOrientation(_ exercise: Exercise) -> MuscleMapView.Orientation {
        let posterior: Set<String> = ["lats", "middle back", "lower back", "traps", "glutes", "hamstrings", "calves", "triceps"]
        return exercise.primaryMuscles.contains(where: posterior.contains) ? .back : .front
    }
}
