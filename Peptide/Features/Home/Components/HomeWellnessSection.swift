import SwiftUI

/// "Wellness" block of the merged Today scroll. The daily check-in
/// is a logging action (not an analytical surface), which is why it
/// stays on Today even though the correlation cards it feeds moved
/// to Insights in Phase 32.
///
/// The check-in sheet pre-fills with yesterday's values so the user's
/// first interaction is a one-tap nudge instead of resetting five
/// sliders from neutral.
struct HomeWellnessSection: View {
    @Environment(DataStore.self) private var dataStore

    /// Built per parent render, so the card empties at midnight even
    /// though no profile property it reads changed.
    var day: Date = Calendar.current.startOfDay(for: Date())

    @State private var showOutcomeCheckIn = false

    /// No section header: the card titles itself "Today's check-in".
    var body: some View {
        DailyCheckInCard(
            todayEntry: dataStore.outcome(for: day),
            onTap: { showOutcomeCheckIn = true }
        )
        .dailyCheckInSheet(isPresented: $showOutcomeCheckIn)
    }
}

/// Today's check-in sheet, pre-filled with today's entry or else the
/// most recent earlier one. Shared so Today can open it even when the
/// user has hidden this section.
private struct DailyCheckInSheetModifier: ViewModifier {
    @Environment(DataStore.self) private var dataStore
    @Binding var isPresented: Bool

    /// Most recent outcome entry from before today. Used to pre-fill
    /// the check-in sheet so the user nudges yesterday's values
    /// instead of starting from a neutral 3 across the board.
    private var yesterdayOutcome: OutcomeEntry? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return dataStore.profile.outcomeHistory
            .filter { $0.date < today }
            .max { $0.date < $1.date }
    }

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            OutcomeCheckInSheet(
                date: Date(),
                initial: dataStore.outcome(),
                previousEntry: yesterdayOutcome,
                onSave: { entry in
                    dataStore.logOutcome(entry)
                    Haptics.success()
                    isPresented = false
                },
                onCancel: { isPresented = false }
            )
            .liquidGlassPresentation()
        }
    }
}

extension View {
    func dailyCheckInSheet(isPresented: Binding<Bool>) -> some View {
        modifier(DailyCheckInSheetModifier(isPresented: isPresented))
    }
}
