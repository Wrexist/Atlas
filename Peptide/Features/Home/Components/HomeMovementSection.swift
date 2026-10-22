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
    @Environment(AppState.self) private var appState
    /// Today's session count and minutes, derived once per store
    /// revision by `HomeView` rather than fetched from `body`.
    let summary: (count: Int, minutes: Int)

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HomeSectionHeader(eyebrow: "Movement", title: "Training")

            WorkoutCard(
                sessionCountToday: summary.count,
                durationMinutesToday: summary.minutes,
                onTap: {
                    Haptics.selection()
                    appState.selectedTab = .train
                }
            )
        }
    }
}
