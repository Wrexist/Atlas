import XCTest
@testable import Peptide

final class WristTemperatureEngineTests: XCTestCase {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2025-10-10 00:00 UTC.
    private let dayZero = Date(timeIntervalSince1970: 1_760_054_400)

    /// A night's reading ending at 07:00 on `day`.
    private func reading(day: Int, _ celsius: Double) -> WristTemperatureEngine.Reading {
        WristTemperatureEngine.Reading(date: dayZero.addingTimeInterval(Double(day) * 86_400 + 7 * 3600), celsius: celsius)
    }

    private func now(day: Int, hour: Double = 9) -> Date {
        dayZero.addingTimeInterval(Double(day) * 86_400 + hour * 3600)
    }

    func test_deviation_lastNightAboveMedianBaseline_isPositive() throws {
        let baseline = [35.0, 35.2, 35.1, 34.9, 35.1, 36.5].enumerated().map { reading(day: $0.offset, $0.element) }
        let readings = baseline + [reading(day: 6, 35.6)]

        let deviation = try XCTUnwrap(WristTemperatureEngine.deviation(readings: readings, now: now(day: 6), calendar: utc))

        // Median of 35.0, 35.2, 35.1, 34.9, 35.1, 36.5 is 35.1; the 36.5 outlier doesn't drag it.
        XCTAssertEqual(deviation.celsius, 0.5, accuracy: 0.0001)
        XCTAssertEqual(deviation.baselineNights, 6)
        XCTAssertEqual(deviation.night, utc.startOfDay(for: now(day: 6)))
    }

    func test_deviation_coolerNight_isNegative() throws {
        let readings = (0..<5).map { reading(day: $0, 35.4) } + [reading(day: 5, 35.0)]

        let deviation = try XCTUnwrap(WristTemperatureEngine.deviation(readings: readings, now: now(day: 5), calendar: utc))

        XCTAssertEqual(deviation.celsius, -0.4, accuracy: 0.0001)
    }

    func test_deviation_fewerThanFiveBaselineNights_isNil() {
        let readings = (0..<4).map { reading(day: $0, 35.2) } + [reading(day: 4, 35.5)]

        XCTAssertNil(WristTemperatureEngine.deviation(readings: readings, now: now(day: 4), calendar: utc))
    }

    func test_deviation_latestNightOlderThanYesterday_isNil() {
        let readings = (0..<6).map { reading(day: $0, 35.2) }

        XCTAssertNil(WristTemperatureEngine.deviation(readings: readings, now: now(day: 7), calendar: utc))
    }

    func test_deviation_yesterdaysNightBeforeTodaySyncs_stillShows() {
        let readings = (0..<6).map { reading(day: $0, 35.2) }

        XCTAssertNotNil(WristTemperatureEngine.deviation(readings: readings, now: now(day: 6), calendar: utc))
    }

    func test_deviation_splitNight_averagesIntoOneReading() throws {
        let baseline = (0..<5).map { reading(day: $0, 35.0) }
        let lastNight = [
            reading(day: 5, 35.2),
            WristTemperatureEngine.Reading(date: now(day: 5, hour: 4), celsius: 35.6),
        ]

        let deviation = try XCTUnwrap(
            WristTemperatureEngine.deviation(readings: baseline + lastNight, now: now(day: 5), calendar: utc)
        )

        XCTAssertEqual(deviation.celsius, 0.4, accuracy: 0.0001)
        XCTAssertEqual(deviation.baselineNights, 5)
    }

    func test_deviation_longHistory_baselineCapsAtWindow() throws {
        let nights = WristTemperatureEngine.baselineWindowNights + 10
        let readings = (0...nights).map { reading(day: $0, 35.0) }

        let deviation = try XCTUnwrap(WristTemperatureEngine.deviation(readings: readings, now: now(day: nights), calendar: utc))

        XCTAssertEqual(deviation.baselineNights, WristTemperatureEngine.baselineWindowNights)
        XCTAssertEqual(deviation.celsius, 0, accuracy: 0.0001)
    }

    func test_displayDelta_imperial_scalesWithoutOffset() {
        XCTAssertEqual(WristTemperatureEngine.displayDelta(0.5, unit: .imperial), 0.9, accuracy: 0.0001)
        XCTAssertEqual(WristTemperatureEngine.displayDelta(-0.5, unit: .metric), -0.5, accuracy: 0.0001)
    }
}
