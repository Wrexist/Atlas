import SwiftUI

/// The same completed-set projection in active, finished and historical workouts.
struct SessionMuscleCard: View {
    let session: WorkoutSession
    @State private var inspectedMuscle: AnatomicalMuscle?
    @State private var facing: BodyFacing = .both
    @State private var library = ExerciseLibrary.shared

    private var highlights: [AnatomicalMuscle: MuscleHighlight] {
        MuscleMapView.highlights(forExercises: WeeklyMuscleHeatmap.completedExercises(
            from: session, library: library
        ))
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Muscles trained")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(caption)
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if !highlights.isEmpty {
                        BodyFacingButton(facing: $facing)
                    }
                }
                TrainingBodyExplorer(
                    highlights: highlights,
                    side: $facing,
                    primaryColor: AppColor.trainingPrimaryMuscleTint,
                    secondaryColor: AppColor.trainingSecondaryMuscleTint,
                    onIdentify: { inspectedMuscle = $0 }
                )
                .frame(maxWidth: .infinity)
            }
        }
        .task { await library.load() }
        .sheet(item: $inspectedMuscle) { muscle in
            MuscleHistorySheet(
                muscle: muscle,
                history: WeeklyMuscleHeatmap.history(
                    for: muscle, from: [session], library: library, days: nil
                ),
                // No sessions: the only one is the workout already on
                // screen, and linking to it nests the same detail forever.
                periodLabel: String(localized: "This workout")
            )
        }
    }

    private var caption: LocalizedStringKey {
        if !highlights.isEmpty { return "Based on completed working sets in this workout." }
        return session.isActive
            ? "Complete a working set to light up your muscles."
            : "No completed working sets were logged."
    }
}
