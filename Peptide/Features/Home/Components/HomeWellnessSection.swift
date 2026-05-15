import SwiftUI

/// "Wellness" block of the merged Today scroll. The daily check-in
/// is a logging action (not an analytical surface), which is why it
/// stays on Today even though the correlation cards it feeds moved
/// to Insights in Phase 32.
///
/// Owns its own check-in sheet because no other surface presents
/// it, and pre-fills with yesterday's values so the user's first
/// interaction is a one-tap nudge instead of resetting five
/// sliders from neutral.
struct HomeWellnessSection: View {
    @Environment(DataStore.self) private var dataStore

    @State private var showOutcomeCheckIn = false

    /// Most recent outcome entry from before today. Used to pre-fill
    /// the check-in sheet so the user nudges yesterday's values
    /// instead of starting from a neutral 3 across the board.
    private var yesterdayOutcome: OutcomeEntry? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return dataStore.profile.outcomeHistory
            .filter { !calendar.isDate($0.date, inSameDayAs: today) }
            .max { $0.date < $1.date }
    }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            HomeSectionHeader(eyebrow: "Wellness", title: "How you're feeling")

            DailyCheckInCard(
                todayEntry: dataStore.outcome(),
                onTap: { showOutcomeCheckIn = true }
            )
        }
        .sheet(isPresented: $showOutcomeCheckIn) {
            OutcomeCheckInSheet(
                date: Date(),
                initial: dataStore.outcome(),
                previousEntry: yesterdayOutcome,
                onSave: { entry in
                    dataStore.logOutcome(entry)
                    showOutcomeCheckIn = false
                },
                onCancel: { showOutcomeCheckIn = false }
            )
        }
    }
}
