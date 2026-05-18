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
        let tabs = ["Today", "Train", "Meals", "Biology", "Library"]
        for tab in tabs {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected, "\(tab) tab should be selected")
        }
    }

    func test_libraryTab_loads() {
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.tabBars.buttons["Library"].isSelected)
    }

    func test_trainTab_loads() {
        app.tabBars.buttons["Train"].tap()
        XCTAssertTrue(app.tabBars.buttons["Train"].isSelected)
    }

    func test_mealsTab_loads() {
        app.tabBars.buttons["Meals"].tap()
        XCTAssertTrue(app.tabBars.buttons["Meals"].isSelected)
    }

    func test_biologyTab_loads() {
        app.tabBars.buttons["Biology"].tap()
        XCTAssertTrue(app.tabBars.buttons["Biology"].isSelected)
    }
}
