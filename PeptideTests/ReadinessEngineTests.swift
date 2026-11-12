import XCTest
@testable import Peptide

final class ReadinessEngineTests: XCTestCase {

    private func assess(
        hrv: Double? = nil, hrvBaseline: Double? = 60,
        rhr: Double? = nil, rhrBaseline: Double? = 55,
        sleep: Double? = nil
    ) -> ReadinessEngine.Assessment {
        ReadinessEngine.assess(RecoveryScoreEngine.Inputs(
            recentHRV: hrv, baselineHRV: hrvBaseline,
            recentRHR: rhr, baselineRHR: rhrBaseline,
            lastSleepHours: sleep
        ))
    }

    // MARK: - Missing data

    func test_noData_isNormal() {
        XCTAssertEqual(assess(), .unknown)
        XCTAssertEqual(assess().level, .normal)
    }

    func test_readingsWithoutBaselines_areIgnored() {
        XCTAssertEqual(assess(hrv: 20, hrvBaseline: nil, rhr: 90, rhrBaseline: nil), .unknown)
    }

    func test_onlyGoodSleep_isNormalNotPenalised() {
        XCTAssertEqual(assess(sleep: 8).level, .normal)
    }

    func test_missingSleep_doesNotBlockReady() {
        XCTAssertEqual(assess(hrv: 66).level, .ready)
    }

    // MARK: - Thresholds

    func test_hrvJustAboveLowThreshold_isNormal() {
        XCTAssertEqual(assess(hrv: 51.6, sleep: 7.5).level, .normal)   // 0.86 × baseline
    }

    func test_hrvBelowLowThreshold_isLow() {
        XCTAssertEqual(assess(hrv: 50.4, sleep: 8), .init(level: .low, reason: .hrvBelowBaseline))   // 0.84
    }

    func test_restingHeartRateWellAboveBaseline_isLow() {
        XCTAssertEqual(assess(rhr: 59.4), .init(level: .low, reason: .restingHeartRateAboveBaseline))   // 1.08
    }

    func test_restingHeartRateSlightlyUp_isNormal() {
        XCTAssertEqual(assess(rhr: 58).level, .normal)   // 1.05
    }

    func test_shortSleep_isLow() {
        XCTAssertEqual(assess(hrv: 60, sleep: 5.5), .init(level: .low, reason: .shortSleep))
    }

    func test_sixHoursSleep_isNotShort() {
        XCTAssertEqual(assess(sleep: 6).level, .normal)
    }

    func test_hrvDeficit_outranksShortSleepAsTheReason() {
        XCTAssertEqual(assess(hrv: 40, sleep: 4).reason, .hrvBelowBaseline)
    }

    func test_highHRVAndRested_isReady() {
        XCTAssertEqual(assess(hrv: 66, rhr: 54, sleep: 7.5), .init(level: .ready, reason: .hrvAboveBaseline))
    }

    func test_highHRVButShortishSleep_isNormal() {
        XCTAssertEqual(assess(hrv: 66, sleep: 6.5).level, .normal)
    }

    func test_highHRVButRacingHeart_isLow() {
        XCTAssertEqual(assess(hrv: 70, rhr: 62).level, .low)
    }

    // MARK: - Keep last good reading

    /// Stockholm, so the day boundary sits away from the UTC midnight CI runs on.
    private var stockholm: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        stockholm.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    private let low = ReadinessEngine.Assessment(level: .low, reason: .hrvBelowBaseline)

    func test_emptyReadSameDay_keepsLastLowReading() {
        let last = ReadinessEngine.Reading(assessment: low, measuredAt: date(10, 7))
        let kept = ReadinessEngine.retained(fresh: .unknown, last: last, now: date(10, 18), calendar: stockholm)
        XCTAssertEqual(kept, low)
    }

    func test_emptyReadNextDay_dropsYesterdaysReading() {
        let last = ReadinessEngine.Reading(assessment: low, measuredAt: date(10, 23, 30))
        let kept = ReadinessEngine.retained(fresh: .unknown, last: last, now: date(11, 0, 30), calendar: stockholm)
        XCTAssertEqual(kept, .unknown)
    }

    func test_emptyReadAfterUTCMidnightBeforeLocalMidnight_keepsReading() {
        // 00:30 in Stockholm is 23:30 on the 9th in UTC; the user's own day decides.
        let last = ReadinessEngine.Reading(assessment: low, measuredAt: date(10, 0, 30))
        let kept = ReadinessEngine.retained(fresh: .unknown, last: last, now: date(10, 22), calendar: stockholm)
        XCTAssertEqual(kept, low)
    }

    func test_realReading_replacesLastReading() {
        let last = ReadinessEngine.Reading(assessment: low, measuredAt: date(10, 7))
        let fresh = ReadinessEngine.Assessment(level: .normal, reason: .typical)
        XCTAssertEqual(ReadinessEngine.retained(fresh: fresh, last: last, now: date(10, 9), calendar: stockholm), fresh)
    }

    func test_emptyReadWithoutLastReading_isUnknown() {
        XCTAssertEqual(ReadinessEngine.retained(fresh: .unknown, last: nil, now: date(10, 9), calendar: stockholm), .unknown)
    }

    func test_reading_roundTripsThroughJSON() throws {
        let reading = ReadinessEngine.Reading(assessment: low, measuredAt: date(10, 7))
        let decoded = try JSONDecoder().decode(ReadinessEngine.Reading.self, from: JSONEncoder().encode(reading))
        XCTAssertEqual(decoded, reading)
    }
}
