import SwiftUI

/// "Movement" block of the merged Today scroll. Just the workout
/// summary card today — kept its own component file so the section
/// can grow later (HRV trend, training plan card, weekly volume)
/// without re-flowing HomeView.
///
/// On today, tapping the card switches to the Train tab; a browsed past
/// day is a read-only record. It used to push the
/// legacy `WorkoutDetailView` "Workout Tracker" — a parallel workout
/// surface, and the only presenter that screen had left — so Today
/// and Train told two different training stories (Product
/// Architecture 07: duplicate destinations removed; the Train tab is
/// the one training home).
struct HomeMovementSection: View {
    @Environment(AppState.self) private var appState
    /// The shown day's session count and minutes, derived once per
    /// store revision by `HomeView` rather than fetched from `body`.
    let summary: (count: Int, minutes: Int)
    var isPastDay = false

    /// Nil on a past day, which leaves the card a plain record.
    private var openTrain: (() -> Void)? {
        guard !isPastDay else { return nil }
        return {
            Haptics.selection()
            appState.selectedTab = .train
        }
    }

    /// No section header: the card already titles itself "Today's
    /// training", and a second heading above it read as a stutter.
    var body: some View {
        WorkoutCard(
            sessionCountToday: summary.count,
            durationMinutesToday: summary.minutes,
            onTap: openTrain,
            isPastDay: isPastDay
        )
    }
}
