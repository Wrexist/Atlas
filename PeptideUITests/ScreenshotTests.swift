import XCTest

/// Captures full-screen screenshots of every main surface so a PR can show
/// real before/after app captures (not code renders).
///
/// Boots the app in **ScreenshotMode** — the app's polished demo-data state
/// — via launch arguments, so every tab is populated and deterministic.
/// Each capture is attached with `.keepAlways` so it survives into the
/// `.xcresult`, which the `screenshots` workflow exports as PNGs.
///
/// Three passes, because the two most recent design changes are invisible to
/// a single default-appearance run:
///
/// - **Dark, default type** — the appearance the app shipped with.
/// - **Light** — every `AppColor` surface and ink token became
///   trait-resolving, and no screen had ever been rendered in light mode.
/// - **Accessibility XXXL** — 393 call sites moved onto a six-step type
///   scale, and `AppFont.scaled` routes through `UIFontMetrics`; the largest
///   content-size category is where truncation would show up.
///
/// Opt-in only: run via the dedicated `Screenshots` workflow (or the
/// `run-ui-tests` label). See `.github/workflows/screenshots.yml`.
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    /// Tab bar buttons in display order. Today is the launch tab, so it's
    /// captured before any tap.
    private static let secondaryTabs = ["Train", "Meals", "Biology", "Library"]

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Passes

    func test_captureAllTabs() {
        launch(appearance: "dark")
        captureAllTabs(prefix: "dark")
    }

    /// Light mode is driven through the app's own `appDisplayMode` default —
    /// the same key `ThemeManager` reads — rather than the simulator's
    /// appearance, because that's the switch a user actually flips.
    func test_captureAllTabs_lightMode() {
        launch(appearance: "light")
        captureAllTabs(prefix: "light")
    }

    /// Largest accessibility content-size category. Anything that truncates,
    /// clips, or overlaps at this size is a layout bug, not a preference.
    func test_captureAllTabs_accessibilityTextSize() {
        launch(
            appearance: "dark",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        captureAllTabs(prefix: "xxxl")
    }

    // MARK: - Helpers

    private func launch(appearance: String, extraArguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        // `-key value` pairs land in the NSArgumentDomain, so these read
        // back through UserDefaults at launch: skip onboarding, flip
        // ScreenshotMode on (its key is read by ScreenshotMode.init), and
        // pin the appearance (read by ThemeManager.init).
        //
        // Also pre-stamp WhatsNewService's "last seen tour version" key
        // (`WhatsNewService.currentTourVersion`, currently "v3.1-biology").
        // `bootstrapForFreshInstallIfNeeded` only stamps this on launch when
        // `hasCompletedOnboarding` is still false, but this suite launches
        // with onboarding pre-completed above — so on a fresh simulator the
        // stamp is never written, `shouldShowTour` sees a nil last-seen
        // version, and PeptideApp presents the full-screen, drag-to-dismiss-
        // disabled WhatsNewTourSheet ~450ms after the first `.active` scene
        // phase. That sheet then silently absorbs every subsequent tab tap
        // in `captureAllTabs` (each tap lands on the sheet's own "Continue"
        // control, which happens to sit in the same screen region as the
        // real tab bar), so every capture past the first ends up showing a
        // tour page instead of the tab it's named after, and the Library
        // tab / paywall step are never reached. Stamping the key up front
        // matches how a real existing user (the only audience this tour
        // targets) would already have it set, and keeps the suite in sync
        // if `currentTourVersion` is bumped again.
        app.launchArguments = [
            "-hasCompletedOnboarding", "YES",
            "-com.peptidesai.app.screenshotMode.enabled", "YES",
            "-appDisplayMode", appearance,
            "-com.peptidesai.app.whatsNew.lastSeenVersion", "v3.1-biology",
        ] + extraArguments
        app.launch()
    }

    /// Walks the five tabs and captures each. Tabs that don't appear are
    /// skipped rather than failing, so one renamed tab can't lose the
    /// whole run. The Biology tab additionally opens the paywall — see
    /// `capturePaywall`.
    ///
    /// A first-launch system dialog (the notifications permission prompt)
    /// can appear at any point in this sequence — it isn't gated on a
    /// specific screen, so it can land between a tab tap and its capture.
    /// Left unhandled, the alert doesn't block the *next* tap (the tab bar
    /// sits underneath it and still receives touches), so the tap silently
    /// switches tabs while the alert stays on top for one more capture,
    /// pushing every subsequent screenshot's label one tab out of sync and
    /// dropping the last tab (and the paywall step) off the end entirely.
    /// `dismissSystemAlertIfNeeded()` clears it before it can do that.
    private func captureAllTabs(prefix: String) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        dismissSystemAlertIfNeeded()
        capture(named: "\(prefix)-01-Today")

        for (offset, tab) in Self.secondaryTabs.enumerated() {
            let button = app.tabBars.buttons[tab]
            guard button.waitForExistence(timeout: 5) else { continue }
            button.tap()
            dismissSystemAlertIfNeeded()
            capture(named: String(format: "%@-%02d-%@", prefix, offset + 2, tab))

            if tab == "Biology" {
                capturePaywall(prefix: prefix, slot: offset + 3)
            }
        }
    }

    /// Dismisses a system permission alert (e.g. the notifications prompt)
    /// if one is currently on screen. Cheap to call speculatively — the
    /// wait only costs real time when an alert is actually present.
    private func dismissSystemAlertIfNeeded() {
        let alert = app.alerts.firstMatch
        guard alert.waitForExistence(timeout: 0.5) else { return }
        if alert.buttons["Allow"].exists {
            alert.buttons["Allow"].tap()
        } else if alert.buttons["Don't Allow"].exists {
            alert.buttons["Don't Allow"].tap()
        }
    }

    /// The paywall (App Store screenshot slot 8). Demo mode always renders
    /// Bio Age locked — `ScreenshotMode` seeds no HealthKit history — so
    /// `BioAgeHeroSection`'s "Unlock with Pro" pill is on screen right
    /// after the Biology capture above. Its `accessibilityLabel` is
    /// "Unlock biological age with Pro" (`BioAgeHeroSection.unlockPill`);
    /// tapping it calls `BiologyView.presentPaywall()`, which presents
    /// `PaywallView` as a sheet.
    ///
    /// `PaywallView`'s `.task` awaits `StoreService.loadProducts()` before
    /// the pricing rows render. The `PeptideUICapture` scheme wires
    /// `Peptide/Resources/Products.storekit` as its test action's
    /// `storeKitConfiguration` (see `project.yml`), so the three real
    /// product IDs resolve locally, in-process, with no network or
    /// sandbox account — the sleep below just gives that local resolution
    /// (and the async trial-eligibility check that follows it) time to
    /// land before the capture.
    ///
    /// Skips rather than fails if the button or the sheet doesn't show,
    /// matching `captureAllTabs`'s per-tab tolerance: a renamed control on
    /// this one screen shouldn't fail the whole capture run.
    private func capturePaywall(prefix: String, slot: Int) {
        let unlockButton = app.buttons["Unlock biological age with Pro"]
        guard unlockButton.waitForExistence(timeout: 5) else { return }
        unlockButton.tap()

        let closeButton = app.buttons["Close"]
        guard closeButton.waitForExistence(timeout: 5) else { return }
        Thread.sleep(forTimeInterval: 2.0)
        dismissSystemAlertIfNeeded()
        capture(named: String(format: "%@-%02d-Paywall", prefix, slot))

        // Dismiss so the loop above can go on to try the Library tab.
        closeButton.tap()
    }

    private func capture(named name: String) {
        // Let the screen settle past its appear animation before grabbing.
        Thread.sleep(forTimeInterval: 1.0)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
