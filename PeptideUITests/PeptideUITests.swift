import XCTest

final class PeptideUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = XCUIApplication.returningUserArguments
        app.launch()
    }

    private static let tabs = ["Today", "Train", "Meals", "Biology", "Habits"]

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func test_appLaunches() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    func test_allTabsAreReachable() {
        for tab in Self.tabs {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected, "\(tab) tab should be selected")
        }
    }

    func test_habitsTab_loads() {
        app.tabBars.buttons["Habits"].tap()
        XCTAssertTrue(app.tabBars.buttons["Habits"].isSelected)
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

    func test_accessibilityAudit_allTabs() throws {
        try auditAllTabs()
    }

    func test_accessibilityAudit_allTabs_atLargestDynamicType() throws {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        try auditAllTabs()
    }

    private func auditAllTabs() throws {
        for tab in Self.tabs {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(tab) tab missing")
            button.tap()
            try app.performAccessibilityAudit(
                for: [.dynamicType, .contrast, .hitRegion, .sufficientElementDescription, .textClipped]
            )
        }
    }
}
