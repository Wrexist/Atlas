import XCTest
@testable import Peptide

final class WorkoutConsistencyEngineTests: XCTestCase {

    func test_callout_zeroSessions_returnsNil() {
        XCTAssertNil(WorkoutConsistencyEngine.callout(sessionsInTrailingWeek: 0))
    }

    func test_callout_oneSession_returnsNil() {
        // A first session this week isn't a consistency signal yet —
        // "1st workout this week" reads as a non sequitur, not a streak.
        XCTAssertNil(WorkoutConsistencyEngine.callout(sessionsInTrailingWeek: 1))
    }

    func test_callout_twoSessions_usesOrdinalSecond() {
        XCTAssertEqual(
            WorkoutConsistencyEngine.callout(sessionsInTrailingWeek: 2),
            "2nd workout this week — you're building consistency."
        )
    }

    func test_callout_threeSessions_usesOrdinalThird() {
        XCTAssertEqual(
            WorkoutConsistencyEngine.callout(sessionsInTrailingWeek: 3),
            "3rd workout this week — you're building consistency."
        )
    }

    func test_callout_fourSessions_usesOrdinalFourth() {
        XCTAssertEqual(
            WorkoutConsistencyEngine.callout(sessionsInTrailingWeek: 4),
            "4th workout this week — you're building consistency."
        )
    }

    func test_callout_elevenSessions_usesOrdinalEleventh() {
        // English ordinal suffix rules special-case 11th/12th/13th
        // (not "11st") — exercising the formatter beyond the single-digit
        // cases guards against a naive suffix implementation regressing
        // into this engine later.
        XCTAssertEqual(
            WorkoutConsistencyEngine.callout(sessionsInTrailingWeek: 11),
            "11th workout this week — you're building consistency."
        )
    }
}
