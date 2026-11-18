import XCTest
@testable import Peptide

final class LoggedCaloriePanelTests: XCTestCase {

    func test_budget_farOverTarget_reportsOverNotReached() {
        XCTAssertEqual(LoggedCaloriePanel.budget(total: 3200, target: 2000), .over(1200))
    }

    func test_budget_withinFivePercent_reportsReached() {
        XCTAssertEqual(LoggedCaloriePanel.budget(total: 2050, target: 2000), .reached)
        XCTAssertEqual(LoggedCaloriePanel.budget(total: 1950, target: 2000), .reached)
    }

    func test_budget_underTarget_reportsWhatIsLeft() {
        XCTAssertEqual(LoggedCaloriePanel.budget(total: 1200, target: 2000), .left(800))
    }

    func test_budget_noTarget_isNil() {
        XCTAssertNil(LoggedCaloriePanel.budget(total: 1200, target: 0))
    }
}
