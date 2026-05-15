import SwiftUI

/// "Movement" block of the merged Today scroll. Just the workout
/// summary card today — kept its own component file so the section
/// can grow later (HRV trend, training plan card, weekly volume)
/// without re-flowing HomeView. The detail push uses
/// `.navigationDestination(isPresented:)`, which requires the host
/// view to provide a NavigationStack ancestor — HomeView already
/// does.
struct HomeMovementSection: View {
    @Environment(DataStore.self) private var dataStore

    @State private var showWorkoutDetail = false

    var body: some View {
        VStack(spacing: Spacing.xl) {
            HomeSectionHeader(eyebrow: "Movement", title: "Training")

            WorkoutCard(
                exerciseCountToday: dataStore.workoutSummary().count,
                durationMinutesToday: dataStore.workoutSummary().minutes,
                onTap: { showWorkoutDetail = true }
            )
        }
        .navigationDestination(isPresented: $showWorkoutDetail) {
            WorkoutDetailView()
                .environment(dataStore)
        }
    }
}
