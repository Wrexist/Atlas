import Foundation

#if canImport(ActivityKit) && canImport(AppIntents)
import ActivityKit
import AppIntents

/// Interactive `LiveActivityIntent` fired by the "Log dose" button
/// on the Dynamic Island / Lock-Screen live activity (iOS 17+).
///
/// Lives in /Shared so both the app target and the widget extension
/// reference the same type. iOS runs this intent **in the live
/// activity's host process** — usually the widget extension — for
/// sub-second latency. Two side effects fire on each tap:
///
///   1. Flip the activity's `ContentState` to `completed = true` so
///      the user sees an instant "Logged" badge without waiting on
///      the main app to wake up.
///   2. Drop a `PendingDoseLogStore.PendingLog` marker in the App
///      Group inbox. The main app drains it on next foreground via
///      `PendingDoseLogProcessor` and toggles the real
///      `ProtocolEntry`.
///
/// This split keeps the widget extension's memory budget tiny — it
/// never touches SwiftData / CloudKit / VialPalette / the full
/// `DataStore` — while still giving the user the immediate visual
/// confirmation an interactive button needs.
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

        // 2) Flip the live activity to its completed state for
        //    instant visual feedback. The app's
        //    `DoseLiveActivityService.markCompleted` will run the
        //    same flip (idempotent) when the marker is drained;
        //    doing it here too means the user sees the "Logged"
        //    badge in <100 ms even before the app wakes up.
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
            await activity.update(ActivityContent(state: updated, staleDate: nil))
        }
        return .result()
    }
}
#endif
