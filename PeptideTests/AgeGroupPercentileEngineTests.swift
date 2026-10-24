import XCTest
@testable import Peptide

final class AgeGroupPercentileEngineTests: XCTestCase {

    func test_vo2Max_atGroupMedian_beatsHalf() {
        // FRIEND men 30–39 median is 42.4.
        XCTAssertEqual(AgeGroupPercentileEngine.betterThan(.vo2Max, value: 42.4, age: 35, sex: .male), 50)
    }

    func test_vo2Max_betweenAnchors_interpolates() {
        // FRIEND women 20–29: 50th 37.6, 75th 44.7; 40 % of the way is the 60th.
        let share = AgeGroupPercentileEngine.betterThan(.vo2Max, value: 37.6 + 0.4 * (44.7 - 37.6), age: 25, sex: .female)
        XCTAssertEqual(share, 60)
    }

    func test_vo2Max_sameReadingOlder_ranksHigher() throws {
        let young = try XCTUnwrap(AgeGroupPercentileEngine.betterThan(.vo2Max, value: 40, age: 25, sex: .male))
        let older = try XCTUnwrap(AgeGroupPercentileEngine.betterThan(.vo2Max, value: 40, age: 55, sex: .male))
        XCTAssertGreaterThan(older, young)
    }

    func test_restingHeartRate_lowerIsBetter() throws {
        // NHANES men 20–39: 25th percentile is 61 bpm, so 61 beats 75 %.
        XCTAssertEqual(AgeGroupPercentileEngine.betterThan(.restingHeartRate, value: 61, age: 30, sex: .male), 75)
        let high = try XCTUnwrap(AgeGroupPercentileEngine.betterThan(.restingHeartRate, value: 85, age: 30, sex: .male))
        XCTAssertLessThan(high, 25)
    }

    func test_readingsBeyondTable_clampToFiveAndNinetyFive() {
        XCTAssertEqual(AgeGroupPercentileEngine.betterThan(.vo2Max, value: 80, age: 30, sex: .male), 95)
        XCTAssertEqual(AgeGroupPercentileEngine.betterThan(.vo2Max, value: 10, age: 30, sex: .male), 5)
        XCTAssertEqual(AgeGroupPercentileEngine.betterThan(.restingHeartRate, value: 40, age: 30, sex: .female), 95)
    }

    func test_agesOutsideTable_useNearestRow() {
        XCTAssertEqual(
            AgeGroupPercentileEngine.betterThan(.vo2Max, value: 48.0, age: 18, sex: .male),
            AgeGroupPercentileEngine.betterThan(.vo2Max, value: 48.0, age: 25, sex: .male)
        )
        XCTAssertEqual(
            AgeGroupPercentileEngine.betterThan(.vo2Max, value: 24.4, age: 90, sex: .male),
            50
        )
    }

    func test_sexWithoutTable_hasNoPlacement() {
        XCTAssertNil(AgeGroupPercentileEngine.betterThan(.vo2Max, value: 40, age: 30, sex: .unspecified))
        XCTAssertNil(AgeGroupPercentileEngine.betterThan(.restingHeartRate, value: 60, age: 30, sex: .other))
    }
}
