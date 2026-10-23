import XCTest
@testable import Peptide

/// Pins what Siri says for "How's my streak?".
final class ShowStreakIntentTests: XCTestCase {

    private func readout(
        tracksDoses: Bool = true,
        doseStreak: Int = 0,
        doseBest: Int = 0,
        mealStreak: Int = 0,
        mealBest: Int = 0
    ) -> String {
        var resource = ShowStreakIntent.readout(ShowStreakIntent.Snapshot(
            tracksDoses: tracksDoses,
            doseStreak: doseStreak,
            doseBest: doseBest,
            mealStreak: mealStreak,
            mealBest: mealBest
        ))
        // The assertions read English words; pin it over the host's language.
        resource.locale = Locale(identifier: "en")
        return String(localized: resource)
    }

    func test_noProtocols_omitsTheDoseLine() {
        let spoken = readout(tracksDoses: false, mealStreak: 4)
        XCTAssertFalse(spoken.localizedCaseInsensitiveContains("dose"), spoken)
        XCTAssertTrue(spoken.contains("4"), spoken)
    }

    func test_lapsedMealStreak_saysTheBestInDays() {
        let spoken = readout(tracksDoses: false, mealBest: 12)
        XCTAssertTrue(spoken.contains("12"), spoken)
        XCTAssertTrue(spoken.contains("days"), spoken)
    }

    func test_lapsedDoseStreak_saysTheBest() {
        let spoken = readout(doseBest: 9)
        XCTAssertTrue(spoken.contains("9"), spoken)
    }

    func test_nothingToReport_stillAnswers() {
        XCTAssertFalse(readout(tracksDoses: false).isEmpty)
    }
}
