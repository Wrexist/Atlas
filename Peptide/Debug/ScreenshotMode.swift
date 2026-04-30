import SwiftUI

/// Centralized state for App Store screenshot capture. Reachable in
/// DEBUG and TestFlight builds via `ScreenshotTools.isAvailable`; the
/// trigger is hidden in App Store Release.
///
/// Two responsibilities:
/// 1. Toggle the global Pro override on `StoreService` so Pro-gated UI
///    renders unlocked in screenshots without requiring a sandbox purchase.
/// 2. Surface an `isActive` flag that views can observe to hide TestFlight
///    chrome, debug banners, or "Upgrade" CTAs when shooting.
///
/// Toggle from the in-app screenshot control panel (Profile → About →
/// tap Version 7 times).
@MainActor @Observable
final class ScreenshotMode {
    static let shared = ScreenshotMode()

    /// True while the next batch of screenshots is being captured. Persisted
    /// across launches so the simulator boots into the same state during a
    /// shoot session.
    private(set) var isActive: Bool {
        didSet {
            UserDefaults.standard.set(isActive, forKey: Self.activeKey)
            StoreService.shared.overrideProForScreenshots(isActive)
        }
    }

    private static let activeKey = "screenshot_mode_active"

    private init() {
        let stored = UserDefaults.standard.bool(forKey: Self.activeKey)
        self.isActive = stored
        if stored {
            StoreService.shared.overrideProForScreenshots(true)
        }
    }

    func setActive(_ active: Bool) {
        isActive = active
    }

    func toggle() {
        setActive(!isActive)
    }
}
