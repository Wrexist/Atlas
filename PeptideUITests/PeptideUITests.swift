import XCTest

final class PeptideUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func test_appLaunches() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    func test_allTabsAreReachable() {
        let tabs = ["Today", "Library", "Protocols", "Insights", "Profile"]
        for tab in tabs {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected, "\(tab) tab should be selected")
        }
    }

    func test_libraryTab_loads() {
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.tabBars.buttons["Library"].isSelected)
    }

    func test_protocolsTab_loads() {
        app.tabBars.buttons["Protocols"].tap()
        XCTAssertTrue(app.tabBars.buttons["Protocols"].isSelected)
    }

    func test_insightsTab_loads() {
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.tabBars.buttons["Insights"].isSelected)
    }

    func test_profileTab_loads() {
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.tabBars.buttons["Profile"].isSelected)
    }
}
