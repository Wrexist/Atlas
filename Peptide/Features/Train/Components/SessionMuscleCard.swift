import SwiftUI

/// The same completed-set projection in active, finished and historical workouts.
struct SessionMuscleCard: View {
    let session: WorkoutSession
    @State private var inspectedMuscle: AnatomicalMuscle?
    @State private var library = ExerciseLibrary.shared

    private var highlights: [AnatomicalMuscle: MuscleHighlight] {
        MuscleMapView.highlights(forExercises: WeeklyMuscleHeatmap.completedExercises(
            from: session, library: library
        ))
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Muscles trained")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                Text(highlights.isEmpty
                     ? "Complete a working set to light up your muscles."
                     : "Based on completed working sets in this workout.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                MuscleMapView(
                    highlights: highlights,
                    primaryColor: AppColor.trainingPrimaryMuscle,
                    secondaryColor: AppColor.trainingSecondaryMuscle,
                    onIdentify: { inspectedMuscle = $0 }
                )
                .frame(maxWidth: .infinity)
                HStack(spacing: Spacing.lg) {
                    Label("Primary", systemImage: "circle.fill")
                        .foregroundStyle(AppColor.trainingPrimaryMuscle)
                    Label("Secondary", systemImage: "circle.fill")
                        .foregroundStyle(AppColor.trainingSecondaryMuscle)
                }
                .font(AppFont.caption)
                if !highlights.isEmpty {
                    Menu("Explore trained muscles") {
                        ForEach(AnatomicalMuscle.allCases.filter { highlights[$0] != nil }, id: \.self) { muscle in
                            Button(muscle.displayName) { inspectedMuscle = muscle }
                        }
                    }
                    .font(AppFont.subheadline)
                    .accessibilityIdentifier("explore-trained-muscles")
                }
            }
        }
        .sheet(item: $inspectedMuscle) { muscle in
            MuscleHistorySheet(
                muscle: muscle,
                history: WeeklyMuscleHeatmap.history(
                    for: muscle, from: [session], library: library, days: nil
                ),
                periodLabel: "This workout"
            )
        }
    }
}
