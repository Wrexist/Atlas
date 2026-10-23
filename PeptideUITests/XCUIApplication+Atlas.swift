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
    /// sits where the tab bar is), so tab switches silently no-op. The stamp
    /// must equal `currentTourVersion`; `WhatsNewTourStampTests` fails when
    /// a bump leaves it behind.
    static let returningUserArguments = [
        "-hasCompletedOnboarding", "YES",
        "-com.peptidesai.app.whatsNew.lastSeenVersion", "v3.1-biology",
    ]

    /// Launches straight into the fixed demo data `ScreenshotMode` seeds,
    /// so audits judge the same screens on every machine instead of
    /// whatever the simulator's persistent store holds.
    static let demoDataArguments = returningUserArguments + [
        "-com.peptidesai.app.screenshotMode.enabled", "YES",
    ]

    /// Dismisses whichever first-launch overlay (if any) is on screen.
    /// Cheap to call speculatively: each wait only costs real time when
    /// that overlay is actually present.
    ///
    /// - A system permission alert (notifications, HealthKit, camera).
    /// - `HomeView`'s `CycleMilestonePromptSheet`, whose "Not now" button
    ///   sits low enough to overlap the tab bar.
    /// - The screenshot-mode reminder, which overlaps the tab bar on
    ///   compact phones.
    ///
    /// Left unhandled, any of them silently absorbs the next tap, so a tab
    /// switch no-ops.
    func dismissOverlaysIfNeeded() {
        // Permission prompts are owned by SpringBoard, not the app, so
        // `alerts` never sees them.
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 0.5) {
            if alert.buttons["Allow"].exists {
                alert.buttons["Allow"].tap()
            } else if alert.buttons["Don't Allow"].exists {
                alert.buttons["Don't Allow"].tap()
            }
        }

        let notNow = buttons["Not now"]
        if notNow.waitForExistence(timeout: 0.5) {
            notNow.tap()
        }
        // Hide only the reminder; tapping its main body would exit demo mode.
        let hideReminder = buttons["Hide screenshot mode reminder"]
        if hideReminder.waitForExistence(timeout: 0.5) {
            hideReminder.tap()
        }
    }
}
