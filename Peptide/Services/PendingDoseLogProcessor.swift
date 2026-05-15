import Foundation

/// Drains the `PendingDoseLogStore` inbox and applies each queued
/// log to the running `DataStore`. Called on every transition to
/// `.active` so a tap on the Live Activity's "Log dose" button
/// flushes through within milliseconds of the user returning to
/// the app — and reliably even if they never return (the next
/// cold launch picks up pending markers the same way).
///
/// Also subscribes to a Darwin notification posted by the widget
/// extension when a marker is enqueued, so a tap-and-stay-in-app
/// flow (user is foregrounded but on a different tab) flushes
/// the marker the instant it's queued without waiting on a
/// scene-phase transition.
///
/// The pure-function shape on `drain` lets us unit-test the drain
/// pass against a fake defaults suite without standing up a full
/// scene phase.
@MainActor
enum PendingDoseLogProcessor {

    /// Token returned by `startObserving` that owns the Darwin
    /// notification subscription. Keep this alive on the host
    /// (PeptideApp) for the duration of the scene — when the
    /// token deallocates the observer is removed.
    final class ObservationToken {
        deinit {
            CFNotificationCenterRemoveEveryObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
    }

    /// Subscribes to the cross-process "marker queued"
    /// notification. The callback hops back onto the main actor
    /// before draining so all DataStore mutations stay
    /// MainActor-isolated. Caller retains the returned token.
    static func startObserving(_ dataStore: DataStore) -> ObservationToken {
        let token = ObservationToken()
        let observer = Unmanaged.passUnretained(token).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, _, _, _, _ in
                Task { @MainActor in
                    // Resolve through `DataStore.current` so the
                    // observer doesn't capture a stale reference if
                    // the app rebuilt its store (unlikely but
                    // possible during onboarding).
                    guard let store = DataStore.current else { return }
                    PendingDoseLogProcessor.drain(into: store)
                    DoseLiveActivityService.shared.reconcile(entries: store.entries)
                }
            },
            CrossProcessNotification.pendingDoseLogQueued as CFString,
            nil,
            .deliverImmediately
        )
        return token
    }

    /// Drains every queued log and toggles the matching entry on
    /// `dataStore`. Returns the count of entries that were
    /// actually flipped so callers can decide whether to nudge
    /// downstream side effects (widget timeline reload, watch
    /// sync) once instead of N times.
    @discardableResult
    static func drain(into dataStore: DataStore, defaults: UserDefaults? = nil) -> Int {
        let pending = PendingDoseLogStore.drain(defaults: defaults)
        guard !pending.isEmpty else { return 0 }

        var applied = 0
        for log in pending {
            guard let entry = dataStore.entries.first(where: { $0.id == log.entryId }),
                  !entry.completed
            else { continue }
            // Use the in-app toggle path so every downstream
            // listener (achievements, streak math, widget reload,
            // live activity reconcile, watch sync) fires exactly
            // as if the user had tapped the row in the UI.
            dataStore.toggleEntry(entry.id)
            applied += 1
        }
        if applied > 0 {
            dataStore.flushPendingSave()
        }
        return applied
    }
}
