import Foundation

#if canImport(ActivityKit) && canImport(AppIntents)
import ActivityKit
import AppIntents

/// Interactive `LiveActivityIntent` fired by the "Log dose" button
/// on the Dynamic Island / Lock-Screen live activity (iOS 17+).
///
/// Lives in /Shared so both the app target and the widget extension
/// reference the same type. iOS runs a `LiveActivityIntent` in the
/// app's process, launching it in the background if needed. Three side
/// effects fire on each tap:
///
///   1. Drop a `PendingDoseLogStore.PendingLog` marker in the App
///      Group inbox, so the tap survives whatever happens next.
///   2. End the activity on its `completed = true` state so the user
///      sees an instant "Logged" badge that dismisses itself.
///   3. Apply the marker through `PendingDoseLogStore.applyInProcess`
///      before returning: iOS may suspend a background launch as soon
///      as `perform()` returns, before the Darwin-notification drain
///      gets its turn, which would leave the dose due on the widgets
///      and its reminder armed until the next foreground.
@available(iOS 17.0, *)
struct LogDoseLiveActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log dose"
    static let description = IntentDescription(
        "Marks a peptide dose as taken from the lock screen.",
        categoryName: "Doses"
    )
    static let isDiscoverable: Bool = false

    /// UUID of the originating `ProtocolEntry`, encoded as a string
    /// because `@Parameter` doesn't bridge `UUID` directly.
    @Parameter(title: "Entry ID")
    var entryIdString: String

    init() {}

    init(entryId: UUID) {
        self.entryIdString = entryId.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let entryId = UUID(uuidString: entryIdString) else {
            return .result()
        }

        // 1) Queue a marker for the main app to pick up on next
        //    foreground. Stamp `loggedAt` here so the actualTime on
        //    the eventual ProtocolEntry mutation reflects the
        //    moment the user tapped, not whenever the app wakes.
        PendingDoseLogStore.enqueue(
            PendingDoseLogStore.PendingLog(
                entryId: entryId,
                loggedAt: Date()
            )
        )

        // 2) End the live activity on its completed state for
        //    instant visual feedback. Ending it here, rather than
        //    leaving that to `DoseLiveActivityService.markCompleted`,
        //    means the badge clears even when nothing drains the
        //    marker until the user next opens the app.
        let matching = Activity<DoseWindowAttributes>.activities.first {
            $0.attributes.entryId == entryId
        }
        if let activity = matching, !activity.content.state.completed {
            let updated = DoseWindowAttributes.ContentState(
                doseTime: activity.content.state.doseTime,
                windowStart: activity.content.state.windowStart,
                completed: true,
                loggedAt: Date()
            )
            let dismissAt = Date().addingTimeInterval(DoseWindowAttributes.ContentState.loggedBadgeSeconds)
            await activity.end(
                ActivityContent(state: updated, staleDate: nil),
                dismissalPolicy: .after(dismissAt)
            )
        }
        await MainActor.run { PendingDoseLogStore.applyInProcess?() }
        return .result()
    }
}
#endif
