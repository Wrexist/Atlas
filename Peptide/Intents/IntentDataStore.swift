import Foundation

/// Single chokepoint App Intents use to reach the running `DataStore`.
/// Centralises the MainActor hop + "create a fresh store if the app
/// was launched cold to handle this intent" fallback so each intent's
/// `perform()` stays focused on intent-specific logic.
///
/// Intents can fire in three states:
///
///   1. App is foregrounded — `DataStore.current` is already set,
///      mutations flow through the same code path as a tap.
///   2. App is backgrounded but alive — same.
///   3. App is terminated and iOS just spun it up for the intent —
///      `DataStore.current` may be nil for a few milliseconds before
///      `PeptideApp.init` finishes; this helper constructs a fresh
///      `DataStore` from disk in that window so the intent never
///      sees an empty state.
///
/// All access is `@MainActor`-isolated because `DataStore` is
/// MainActor-isolated. Intents call this inside `MainActor.run { ... }`.
@MainActor
enum IntentDataStore {

    /// Returns the running `DataStore`, falling back to a fresh
    /// disk-backed one if the app was just launched for an intent
    /// and the SwiftUI scene hasn't initialised its copy yet.
    static func resolve() -> DataStore {
        if let existing = DataStore.current { return existing }
        let fresh = DataStore()
        DataStore.current = fresh
        return fresh
    }

    /// Run a synchronous mutation, then force a save so the change
    /// is durable before the intent's `perform()` returns. Without
    /// the flush, the debounced auto-save can lose data when iOS
    /// terminates the app a few hundred ms after the intent finishes.
    static func performAndFlush(_ mutate: (DataStore) -> Void) {
        let store = resolve()
        mutate(store)
        store.flushPendingSave()
    }
}
