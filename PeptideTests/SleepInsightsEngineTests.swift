import XCTest
@testable import Peptide

final class SleepInsightsEngineTests: XCTestCase {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2025-10-10 00:00 UTC.
    private let dayZero = Date(timeIntervalSince1970: 1_760_054_400)

    /// A night that starts `bedHour` hours after midnight of `day` (negative
    /// for the evening before) and lasts `hours`, of which `awake` hours
    /// are spent awake.
    private func night(
        day: Int,
        bedHour: Double = -1,
        hours: Double = 8,
        awake: Double = 0,
        staged: Bool = true
    ) -> SleepScoreEngine.Night {
        let start = dayZero.addingTimeInterval(Double(day) * 86_400 + bedHour * 3600)
        let asleep = (hours - awake) * 3600
        return SleepScoreEngine.Night(
            start: start,
            end: start.addingTimeInterval(hours * 3600),
            deep: staged ? asleep * 0.2 : 0,
            core: staged ? asleep * 0.55 : 0,
            rem: staged ? asleep * 0.25 : 0,
            unspecified: staged ? 0 : asleep,
            awake: awake * 3600
        )
    }

    private func insights(_ nights: [SleepScoreEngine.Night], target: Double = 8) -> SleepInsightsEngine.Insights? {
        SleepInsightsEngine.insights(nights: nights, targetHours: target, calendar: utc)
    }

    func test_insights_fewerThanThreeNights_returnsNil() {
        XCTAssertNil(insights([night(day: 0), night(day: 1)]))
    }

    func test_insights_bedtimesAcrossMidnight_averageNearMidnight() throws {
        // 23:00, 01:00, 00:00 average to midnight, not to noon.
        let result = try XCTUnwrap(insights([
            night(day: 0, bedHour: -1),
            night(day: 1, bedHour: 1),
            night(day: 2, bedHour: 0),
        ]))
        XCTAssertEqual(result.averageBedtime, 0, accuracy: 0.5)
        XCTAssertEqual(result.bedtimeSpread, sqrt(2.0 / 3.0) * 60, accuracy: 0.5)
    }

    func test_insights_sameClockEveryNight_isSteady() throws {
        let result = try XCTUnwrap(insights((0..<7).map { night(day: $0) }))
        XCTAssertEqual(result.bedtimeSpread, 0)
        XCTAssertEqual(result.wakeSpread, 0)
        XCTAssertEqual(result.averageWake, 7 * 60, accuracy: 0.5)
        XCTAssertEqual(result.consistency, .steady)
    }

    func test_insights_bedtimesSwingTwoHours_isIrregular() throws {
        let result = try XCTUnwrap(insights((0..<6).map { night(day: $0, bedHour: $0.isMultiple(of: 2) ? -2 : 1) }))
        XCTAssertEqual(result.consistency, .irregular)
    }

    func test_insights_efficiency_isAsleepOverAsleepPlusAwake() throws {
        let result = try XCTUnwrap(insights((0..<4).map { night(day: $0, hours: 8, awake: 1) }))
        XCTAssertEqual(result.efficiency, 7.0 / 8.0, accuracy: 0.0001)
        XCTAssertEqual(result.averageAsleep, 7 * 3600, accuracy: 1)
    }

    func test_insights_sleepDebt_countsOnlyLastSevenShortNights() throws {
        // Ten nights of 7 h against an 8 h target: only the last seven count.
        let result = try XCTUnwrap(insights((0..<10).map { night(day: $0, hours: 7) }))
        XCTAssertEqual(result.sleepDebt, 7 * 3600, accuracy: 1)
    }

    func test_insights_nightsOverTarget_carryNoDebt() throws {
        let result = try XCTUnwrap(insights((0..<5).map { night(day: $0, hours: 9) }))
        XCTAssertEqual(result.sleepDebt, 0)
    }

    func test_insights_noStagedNights_hasNoStageShares() throws {
        let result = try XCTUnwrap(insights((0..<3).map { night(day: $0, staged: false) }))
        XCTAssertNil(result.stageShares)
    }

    func test_insights_stageShares_sumToOne() throws {
        let shares = try XCTUnwrap(insights((0..<3).map { night(day: $0) })?.stageShares)
        XCTAssertEqual(shares.deep, 0.2, accuracy: 0.0001)
        XCTAssertEqual(shares.rem, 0.25, accuracy: 0.0001)
        XCTAssertEqual(shares.deep + shares.core + shares.rem, 1, accuracy: 0.0001)
    }

    // MARK: - Nights from segments

    func test_nights_napAfterWaking_keepsTheLongerNight() {
        let source = "com.apple.health"
        func segment(_ start: Double, _ hours: Double) -> SleepScoreEngine.Segment {
            let begin = dayZero.addingTimeInterval(start * 3600)
            return .init(stage: .core, start: begin, end: begin.addingTimeInterval(hours * 3600), source: source)
        }
        let nights = SleepScoreEngine.nights(from: [
            segment(-1, 8),   // night ending 07:00 day 0
            segment(14, 1),   // nap ending 15:00 day 0
            segment(23, 7),   // night ending 06:00 day 1
        ], calendar: utc)

        XCTAssertEqual(nights.count, 2)
        XCTAssertEqual(nights.map(\.asleep), [8 * 3600, 7 * 3600])
    }
}
