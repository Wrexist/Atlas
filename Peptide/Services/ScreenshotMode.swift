import Foundation

/// Central toggle for the App Store screenshot capture flow.
/// When active, the running `DataStore` swaps its real protocols /
/// entries / profile for a polished demo seed (every tab populated
/// with believable numbers, a generated weekly recap, a multi-week
/// HRV uptrend, etc.) and stops writing to disk so the user's
/// actual data never leaks into the demo state.
///
/// Lifecycle:
///   1. User flips the toggle on Profile → Settings → Screenshot
///      mode. We persist the flag in UserDefaults and call
///      `activate(in: dataStore)` — in-memory swap, no relaunch
///      needed.
///   2. App relaunches (cold-boot, force-quit, etc.). DataStore's
///      `init` reads `ScreenshotMode.shared.isEnabled` and seeds
///      the demo state up front instead of loading from disk.
///   3. User flips the toggle off. We clear the flag and call
///      `deactivate(in: dataStore)` which reloads real data from
///      disk via `DataStore.reloadFromDisk()`.
///
/// Safety: while screenshot mode is on, `DataStore.isEphemeral`
/// flips to `true` and `performSaveNow()` short-circuits — so
/// every screenshot interaction (logging a dose, adding a meal)
/// stages purely in memory and dies on the next quit-and-relaunch
/// after the toggle goes back off. The real `profile.json`,
/// `entries.json`, etc. on disk are never touched.
@MainActor
@Observable
final class ScreenshotMode {
    static let shared = ScreenshotMode()

    private let defaults: UserDefaults
    /// UserDefaults key. Lives in standard defaults (not the App
    /// Group suite) because nothing outside the app process needs
    /// to read it.
    private static let defaultsKey = "com.peptidesai.app.screenshotMode.enabled"

    /// Observable state — flipping this from the Settings row
    /// triggers the SwiftUI re-render that shows the banner.
    private(set) var isEnabled: Bool
    /// Per-session banner visibility. Tapping the banner's close
    /// button hides it so the user can capture clean screenshots
    /// without the floating reminder bleeding into the frame.
    /// Resets on every cold launch + on every activate, so the
    /// safety net is never permanently lost.
    var isBannerVisible: Bool = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.defaultsKey)
    }

    // MARK: - Public surface

    /// Flip screenshot mode on. Stamps the flag, swaps in demo
    /// data, and marks the store as ephemeral so subsequent
    /// mutations don't hit disk. Idempotent.
    func activate(in dataStore: DataStore) {
        defaults.set(true, forKey: Self.defaultsKey)
        isEnabled = true
        isBannerVisible = true
        applyDemo(to: dataStore)
    }

    /// Flip screenshot mode off. Clears the flag, drops the
    /// ephemeral lock, and reloads real data from disk.
    func deactivate(in dataStore: DataStore) {
        defaults.set(false, forKey: Self.defaultsKey)
        isEnabled = false
        dataStore.exitEphemeralMode()
    }

    /// Called from `DataStore.init` so a cold launch with the
    /// flag stamped on lands directly in the demo state.
    /// `dataStore` is already constructed but hasn't entered
    /// ephemeral mode yet — this is the one chance to seed
    /// before any view reads the state.
    func bootstrapIfActive(in dataStore: DataStore) {
        guard isEnabled else { return }
        applyDemo(to: dataStore)
    }

    // MARK: - Internals

    private func applyDemo(to dataStore: DataStore) {
        let seed = ScreenshotSeedData.build()
        dataStore.enterEphemeralMode(
            profile: seed.profile,
            protocols: seed.protocols,
            entries: seed.entries
        )
    }
}
