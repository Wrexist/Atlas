import SwiftUI

/// Catalog IDs are stable; additional reviewed posters can join this mapping
/// without changing any workout, picker, or history presentation.
enum ExerciseVisualAssets {
    static func poster(for exerciseID: String) -> String? {
        switch exerciseID {
        case "Incline_Dumbbell_Press": return "atlas_incline_dumbbell_press"
        default: return nil
        }
    }

    static func poster(forImagePath path: String?) -> String? {
        guard let id = path?.split(separator: "/").first else { return nil }
        return poster(for: String(id))
    }
}

struct ExerciseHeroView: View {
    let exercise: Exercise?

    var body: some View {
        Group {
            if let exercise, let asset = ExerciseVisualAssets.poster(for: exercise.id) {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Incline dumbbell press, extended position. Chest highlighted in orange; shoulders and triceps in blue.")
            } else if let exercise {
                MuscleMapView(
                    highlights: MuscleMapView.highlights(for: exercise),
                    primaryColor: AppColor.trainingPrimaryMuscle,
                    secondaryColor: AppColor.trainingSecondaryMuscle
                )
                .accessibilityLabel(Text("Muscles worked by \(exercise.name)"))
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(AppFont.statValue)
                    .foregroundStyle(AppColor.textSecondary)
                    .accessibilityLabel("Exercise illustration unavailable")
            }
        }
        .frame(maxWidth: .infinity)
    }
}
