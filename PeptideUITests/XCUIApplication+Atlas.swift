import XCTest

extension XCUIApplication {
    /// `-key value` pairs land in the NSArgumentDomain, so these read back
    /// through UserDefaults at launch and put the app in the state of an
    /// existing user: onboarding done and the current What's New tour seen.
    ///
    /// The tour stamp (`WhatsNewService.currentTourVersion`) matters because
    /// `bootstrapForFreshInstallIfNeeded` only writes it while onboarding is
    /// still incomplete. Skipping onboarding without it leaves the stamp nil,
    /// `shouldShowTour` returns true, and PeptideApp presents the full-screen,
    /// drag-to-dismiss-disabled WhatsNewTourSheet ~450ms after launch. That
    /// sheet then absorbs every following tab tap (its "Continue" control
    /// sits where the tab bar is), so tab switches silently no-op. Keep the
    /// version in sync when `currentTourVersion` is bumped.
    static let returningUserArguments = [
        "-hasCompletedOnboarding", "YES",
        "-com.peptidesai.app.whatsNew.lastSeenVersion", "v3.1-biology",
    ]
}
