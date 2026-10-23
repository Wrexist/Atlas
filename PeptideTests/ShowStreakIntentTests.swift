import XCTest
@testable import Peptide

/// Pins what Siri says for "How's my streak?".
final class ShowStreakIntentTests: XCTestCase {

    private func readout(dose: Int = 0, protocols: Bool, meal: Int = 0, mealBest: Int = 0) -> String {
        String(localized: ShowStreakIntent.readout(.init(
            doseStreak: dose, tracksProtocols: protocols, mealStreak: meal, mealBest: mealBest
        )))
    }

    func test_pausedMealStreak_saysTheBestInDays() {
        XCTAssertEqual(readout(protocols: false, mealBest: 12), "Meal streak paused, best was 12 days.")
    }

    func test_noProtocols_leavesOutTheDoseSentence() {
        XCTAssertFalse(readout(protocols: false, meal: 3).contains("dose"))
    }

    func test_protocolWithLapsedStreak_saysNoActiveDoseStreak() {
        XCTAssertEqual(readout(protocols: true), "No active dose streak.")
    }

    func test_nothingToReport_invitesAFirstLog() {
        XCTAssertEqual(readout(protocols: false), "No streak yet. Log a meal today to start one.")
    }
}
