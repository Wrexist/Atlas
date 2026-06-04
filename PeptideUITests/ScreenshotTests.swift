import XCTest

/// Captures full-screen screenshots of every main surface so a PR can show
/// real before/after app captures (not code renders).
///
/// Boots the app in **ScreenshotMode** — the app's polished demo-data state
/// — via launch arguments, so every tab is populated and deterministic.
/// Each capture is attached with `.keepAlways` so it survives into the
/// `.xcresult`, which the `screenshots` workflow exports as PNGs.
///
/// Opt-in only: run via the dedicated `Screenshots` workflow (or the
/// `run-ui-tests` label). See `.github/workflows/screenshots.yml`.
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // `-key value` pairs land in the NSArgumentDomain, so these read
        // back through UserDefaults at launch: skip onboarding and flip
        // ScreenshotMode on (its key is read by ScreenshotMode.init).
        app.launchArguments = [
            "-hasCompletedOnboarding", "YES",
            "-com.peptidesai.app.screenshotMode.enabled", "YES",
        ]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    /// Walks the five tabs and captures each. Tabs that don't appear are
    /// skipped rather than failing, so one renamed tab can't lose the
    /// whole run.
    func test_captureAllTabs() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        capture(named: "01-Today")

        let tabs = ["Train", "Meals", "Biology", "Library"]
        for (offset, tab) in tabs.enumerated() {
            let button = app.tabBars.buttons[tab]
            guard button.waitForExistence(timeout: 5) else { continue }
            button.tap()
            capture(named: String(format: "%02d-%@", offset + 2, tab))
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
