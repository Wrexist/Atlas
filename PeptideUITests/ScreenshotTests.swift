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
///  - **Dark, default type** — the appearance the app shipped with.
///  - **Light** — every `AppColor` surface and ink token became
///    trait-resolving, and no screen had ever been rendered in light mode.
///  - **Accessibility XXXL** — 393 call sites moved onto a six-step type
///    scale, and `AppFont.scaled` routes through `UIFontMetrics`; the largest
///    content-size category is where truncation would show up.
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
        app.launchArguments = [
            "-hasCompletedOnboarding", "YES",
            "-com.peptidesai.app.screenshotMode.enabled", "YES",
            "-appDisplayMode", appearance,
        ] + extraArguments
        app.launch()
    }

    /// Walks the five tabs and captures each. Tabs that don't appear are
    /// skipped rather than failing, so one renamed tab can't lose the
    /// whole run.
    private func captureAllTabs(prefix: String) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        capture(named: "\(prefix)-01-Today")

        for (offset, tab) in Self.secondaryTabs.enumerated() {
            let button = app.tabBars.buttons[tab]
            guard button.waitForExistence(timeout: 5) else { continue }
            button.tap()
            capture(named: String(format: "%@-%02d-%@", prefix, offset + 2, tab))
        }
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
