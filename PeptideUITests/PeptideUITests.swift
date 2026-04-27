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

    /// iPhone: tab bar. iPad: sidebar list in `NavigationSplitView`.
    private func selectTab(named title: String) {
        if XCUIDevice.shared.orientation == .portrait,
           UIDevice.current.userInterfaceIdiom == .pad {
            app.navigationBars.buttons["PeptideX"].firstMatch.tap()
        }

        let tabButton = app.tabBars.buttons[title]
        if tabButton.exists {
            tabButton.tap()
            return
        }

        let sidebarRow = app.tables.cells.containing(.staticText, identifier: title).element(boundBy: 0)
        if sidebarRow.waitForExistence(timeout: 3) {
            sidebarRow.tap()
            return
        }

        let sidebarStatic = app.tables.staticTexts[title].firstMatch
        XCTAssertTrue(
            sidebarStatic.waitForExistence(timeout: 3),
            "Could not find tab '\(title)' in tab bar or sidebar"
        )
        sidebarStatic.tap()
    }

    private func assertTabSelected(named title: String) {
        let tabButton = app.tabBars.buttons[title]
        if tabButton.exists {
            XCTAssertTrue(tabButton.isSelected, "\(title) tab should be selected")
            return
        }
        let cell = app.tables.cells.containing(.staticText, identifier: title).element(boundBy: 0)
        XCTAssertTrue(cell.waitForExistence(timeout: 2))
        XCTAssertTrue(cell.isSelected, "\(title) sidebar row should be selected")
    }

    func test_appLaunches() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    func test_allTabsAreReachable() {
        let tabs = ["Home", "Peptides", "Protocols", "Analytics", "Profile"]
        for tab in tabs {
            selectTab(named: tab)
            assertTabSelected(named: tab)
        }
    }

    func test_peptidesTab_loads() {
        selectTab(named: "Peptides")
        assertTabSelected(named: "Peptides")
    }

    func test_protocolsTab_loads() {
        selectTab(named: "Protocols")
        assertTabSelected(named: "Protocols")
    }

    func test_analyticsTab_loads() {
        selectTab(named: "Analytics")
        assertTabSelected(named: "Analytics")
    }

    func test_profileTab_loads() {
        selectTab(named: "Profile")
        assertTabSelected(named: "Profile")
    }
}
