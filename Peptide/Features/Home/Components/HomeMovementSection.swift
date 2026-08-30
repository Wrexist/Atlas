import SwiftUI

/// "Movement" block of the merged Today scroll. Just the workout
/// summary card today — kept its own component file so the section
/// can grow later (HRV trend, training plan card, weekly volume)
/// without re-flowing HomeView.
///
/// Tapping the card switches to the Train tab. It used to push the
/// legacy `WorkoutDetailView` "Workout Tracker" — a parallel workout
/// surface, and the only presenter that screen had left — so Today
/// and Train told two different training stories (Product
/// Architecture 07: duplicate destinations removed; the Train tab is
/// the one training home).
struct HomeMovementSection: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState

    var body: some View {
        let summary = dataStore.workoutSummary()
        VStack(spacing: Spacing.xl) {
            HomeSectionHeader(eyebrow: "Movement", title: "Training")

            WorkoutCard(
                exerciseCountToday: summary.count,
                durationMinutesToday: summary.minutes,
                onTap: {
                    Haptics.selection()
                    appState.selectedTab = .train
                }
            )
        }
    }
}
