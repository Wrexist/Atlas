import SwiftUI
import UIKit

struct ExerciseHeroView: View {
    let exercise: Exercise?
    var compact = false
    /// Share cards stay on the art or map: a stock photo is not the user's workout.
    var showsPhotos = true

    /// UIKit's asset cache avoids decoding again on timer ticks. A missing
    /// catalog image falls through to the exercise's photos, then its map.
    private var posterImage: UIImage? {
        guard let exercise, let asset = ExerciseVisualAssets.poster(for: exercise.id) else { return nil }
        return UIImage(named: asset)
    }

    var body: some View {
        Group {
            if let exercise, let posterImage {
                Image(uiImage: posterImage)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(Text("\(exercise.name) illustration"))
            } else if let exercise, compact, showsPhotos, let start = ExercisePhotos.thumbnail(for: exercise.id) {
                Image(uiImage: start)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel(Text("\(exercise.name) start position"))
            } else if let exercise, showsPhotos, let photos = ExercisePhotos.pair(for: exercise.id) {
                ExerciseMovementView(exercise: exercise, photos: photos)
            } else if let exercise {
                ExerciseMuscleMap(
                    exercise: exercise,
                    orientation: compact ? ExerciseMuscleMap.preferredOrientation(for: exercise) : .both
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Muscle map for \(exercise.name). Primary: \(exercise.primaryMuscles.joined(separator: ", ")). Supporting: \(exercise.secondaryMuscles.joined(separator: ", "))."))
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(AppFont.statValue)
                    .foregroundStyle(AppColor.textSecondary)
                    .accessibilityLabel("Exercise illustration unavailable")
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}

/// The exercise's primary and supporting muscles on the anatomy figure.
struct ExerciseMuscleMap: View {
    let exercise: Exercise
    let orientation: MuscleMapView.Orientation

    var body: some View {
        MuscleMapView(
            highlights: MuscleMapView.highlights(for: exercise),
            orientation: orientation,
            primaryColor: AppColor.trainingPrimaryMuscle,
            secondaryColor: AppColor.trainingSecondaryMuscle,
            silhouetteFill: AppColor.textSecondary.opacity(0.10),
            silhouetteStroke: AppColor.textSecondary.opacity(0.30),
            showsSkeleton: false,
            muscleBaseline: AppColor.textSecondary.opacity(0.20),
            tendonStroke: AppColor.textSecondary.opacity(0.25),
            identifiesOnTap: false
        )
    }

    static func preferredOrientation(for exercise: Exercise) -> MuscleMapView.Orientation {
        let posterior: Set<String> = ["lats", "middle back", "lower back", "traps", "glutes", "hamstrings", "calves", "triceps"]
        return exercise.primaryMuscles.contains(where: posterior.contains) ? .back : .front
    }
}
