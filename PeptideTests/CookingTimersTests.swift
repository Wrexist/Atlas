import XCTest
@testable import Peptide

@MainActor
final class CookingTimersTests: XCTestCase {

    func test_reopeningARecipe_getsTheSameRunningTimers() {
        let store = CookingTimerStore()

        let first = store.timers(for: "kalops", recipeName: "Kalops")
        let reopened = store.timers(for: "kalops", recipeName: "Kalops")

        XCTAssertTrue(first === reopened)
    }

    func test_sameStepOfTwoRecipes_hasDifferentNotifications() {
        let store = CookingTimerStore()
        let key = CookingTimers.Key(step: 1, index: 0)

        let pasta = store.timers(for: "pasta", recipeName: "Pasta").identifier(for: key)
        let rice = store.timers(for: "rice", recipeName: "Rice").identifier(for: key)

        XCTAssertNotEqual(pasta, rice)
        XCTAssertTrue(pasta.hasPrefix(CookingTimers.identifierPrefix))
    }
}
