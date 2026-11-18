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

    func test_leavingAnIdleRecipe_dropsItsTimers() {
        let store = CookingTimerStore()
        let first = store.timers(for: "kalops", recipeName: "Kalops")

        store.release(first)

        XCTAssertFalse(first === store.timers(for: "kalops", recipeName: "Kalops"))
    }

    func test_leavingARecipeWithARunningTimer_keepsItsTimers() {
        let store = CookingTimerStore()
        let first = store.timers(for: "kalops", recipeName: "Kalops")
        let key = CookingTimers.Key(step: 0, index: 0)
        first.start(key, seconds: 600)

        store.release(first)

        XCTAssertTrue(first === store.timers(for: "kalops", recipeName: "Kalops"))
        first.cancel(key)
    }

    func test_reopeningInAnotherLanguage_namesTheDishInIt() {
        let store = CookingTimerStore()
        _ = store.timers(for: "kalops", recipeName: "Beef stew")

        let reopened = store.timers(for: "kalops", recipeName: "Kalops")

        XCTAssertEqual(reopened.recipeName, "Kalops")
    }

    func test_keep_replacesAnIdleStandInWithTheShowingPagesTimers() {
        let store = CookingTimerStore()
        let showing = store.timers(for: "kalops", recipeName: "Kalops")
        store.release(showing)
        let standIn = store.timers(for: "kalops", recipeName: "Kalops")

        store.keep(showing, recipeName: "Kalops")

        XCTAssertFalse(standIn === showing)
        XCTAssertTrue(store.timers(for: "kalops", recipeName: "Kalops") === showing)
    }
}
