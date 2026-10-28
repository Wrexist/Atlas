import Foundation

/// Applies End fast taps queued by the fasting Live Activity. A tap for
/// a fast that has since ended or been deleted is dropped.
@MainActor
enum FastingActivityActionProcessor {
    /// `defaults` overrides the shared App Group inbox; tests pass an
    /// isolated suite so a tap never lands where the widget reads.
    static func drain(defaults: UserDefaults? = nil) {
        let queued = PendingFastEndStore.drain(defaults: defaults)
        // Touch the stores only when there is work, so the launch-time
        // drain doesn't open SwiftData for nothing.
        guard !queued.isEmpty else { return }
        // A background launch for the intent has no scene yet; resolving
        // the data store opens the SwiftData container the fasts live in.
        _ = IntentDataStore.resolve()
        let store = FastingStore.shared
        store.load()
        for pending in queued where store.active?.id == pending.fastId {
            store.end(at: pending.endedAt)
        }
    }
}
