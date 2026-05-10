import XCTest
@testable import Peptide

@MainActor
final class ProtocolScheduleCadenceTests: XCTestCase {

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = 12
        return calendar.date(from: c)!
    }

    // MARK: - isInterval

    func test_isInterval_falseWhenNilOrZero() {
        let weekly = ProtocolSchedule(daysOfWeek: [1], timesPerDay: 1, preferredTimes: ["8:00 AM"])
        XCTAssertFalse(weekly.isInterval)

        let zero = ProtocolSchedule(
            daysOfWeek: [1], timesPerDay: 1, preferredTimes: ["8:00 AM"],
            intervalDays: 0
        )
        XCTAssertFalse(zero.isInterval, "0 must not be treated as a valid interval")
    }

    func test_isInterval_trueWhenSet() {
        let s = ProtocolSchedule(
            daysOfWeek: [], timesPerDay: 1, preferredTimes: ["8:00 AM"],
            intervalDays: 3
        )
        XCTAssertTrue(s.isInterval)
    }

    // MARK: - isActive(on:) interval cadence

    func test_isActive_everyThreeDays_firesOnAnchorAndMultiples() {
        let anchor = makeDate(2025, 6, 1) // Sun
        let s = ProtocolSchedule(
            daysOfWeek: [], timesPerDay: 1, preferredTimes: ["8:00 AM"],
            intervalDays: 3, intervalAnchor: anchor
        )

        XCTAssertTrue(s.isActive(on: anchor, calendar: calendar), "Anchor day must fire")
        XCTAssertFalse(s.isActive(on: makeDate(2025, 6, 2), calendar: calendar))
        XCTAssertFalse(s.isActive(on: makeDate(2025, 6, 3), calendar: calendar))
        XCTAssertTrue(s.isActive(on: makeDate(2025, 6, 4), calendar: calendar), "Day +3 must fire")
        XCTAssertFalse(s.isActive(on: makeDate(2025, 6, 5), calendar: calendar))
        XCTAssertTrue(s.isActive(on: makeDate(2025, 6, 7), calendar: calendar), "Day +6 must fire")
    }

    func test_isActive_everyDay_firesEveryDay() {
        let anchor = makeDate(2025, 6, 1)
        let s = ProtocolSchedule(
            daysOfWeek: [], timesPerDay: 1, preferredTimes: ["8:00 AM"],
            intervalDays: 1, intervalAnchor: anchor
        )
        for offset in 0...6 {
            let day = calendar.date(byAdding: .day, value: offset, to: anchor)!
            XCTAssertTrue(s.isActive(on: day, calendar: calendar), "Day +\(offset) must fire on every-1-day")
        }
    }

    func test_isActive_beforeAnchor_returnsFalse() {
        let anchor = makeDate(2025, 6, 10)
        let s = ProtocolSchedule(
            daysOfWeek: [], timesPerDay: 1, preferredTimes: ["8:00 AM"],
            intervalDays: 2, intervalAnchor: anchor
        )
        XCTAssertFalse(s.isActive(on: makeDate(2025, 6, 1), calendar: calendar),
                       "Days before the anchor must be inactive")
    }

    // MARK: - isActive(on:) weekly cadence

    func test_isActive_weeklyCadence_matchesISODayOfWeek() {
        // Mon-Wed-Fri (ISO 1, 3, 5)
        let s = ProtocolSchedule(daysOfWeek: [1, 3, 5], timesPerDay: 1, preferredTimes: ["8:00 AM"])
        let monday = makeDate(2025, 6, 2) // Mon
        let tuesday = makeDate(2025, 6, 3)
        let wednesday = makeDate(2025, 6, 4)
        let sunday = makeDate(2025, 6, 8)

        XCTAssertTrue(s.isActive(on: monday, calendar: calendar))
        XCTAssertFalse(s.isActive(on: tuesday, calendar: calendar))
        XCTAssertTrue(s.isActive(on: wednesday, calendar: calendar))
        XCTAssertFalse(s.isActive(on: sunday, calendar: calendar))
    }

    // MARK: - Display

    func test_daysDescription_intervalCadence() {
        let every3 = ProtocolSchedule(
            daysOfWeek: [], timesPerDay: 1, preferredTimes: ["8:00 AM"],
            intervalDays: 3
        )
        XCTAssertEqual(every3.daysDescription, "Every 3 days")
        XCTAssertEqual(every3.compactDaysDescription, "Every 3d")

        let daily = ProtocolSchedule(
            daysOfWeek: [], timesPerDay: 1, preferredTimes: ["8:00 AM"],
            intervalDays: 1
        )
        XCTAssertEqual(daily.daysDescription, "Every day")
        XCTAssertEqual(daily.compactDaysDescription, "Daily")
    }

    func test_daysDescription_weeklyCadence_unchanged() {
        let weekly = ProtocolSchedule(daysOfWeek: [1, 3, 5], timesPerDay: 1, preferredTimes: ["8:00 AM"])
        XCTAssertEqual(weekly.daysDescription, "Mon, Wed, Fri")
    }

    func test_summary_includesCadence() {
        let interval = ProtocolSchedule(
            daysOfWeek: [], timesPerDay: 2, preferredTimes: ["8:00 AM", "8:00 PM"],
            intervalDays: 4
        )
        XCTAssertEqual(interval.summary, "Every 4d · 2x")
    }

    // MARK: - Codable backwards-compat

    func test_decode_legacyScheduleWithoutInterval_treatedAsWeekly() throws {
        let json = """
        {
            "daysOfWeek": [1, 3, 5],
            "timesPerDay": 1,
            "preferredTimes": ["8:00 AM"]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ProtocolSchedule.self, from: json)
        XCTAssertFalse(decoded.isInterval)
        XCTAssertNil(decoded.intervalDays)
    }

    func test_codableRoundTrip_preservesInterval() throws {
        let anchor = makeDate(2025, 6, 1)
        let original = ProtocolSchedule(
            daysOfWeek: [], timesPerDay: 1, preferredTimes: ["8:00 AM"],
            intervalDays: 5, intervalAnchor: anchor
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ProtocolSchedule.self, from: data)
        XCTAssertEqual(decoded.intervalDays, 5)
        XCTAssertEqual(decoded.intervalAnchor, anchor)
        XCTAssertTrue(decoded.isInterval)
    }

    func test_encode_skipsIntervalFieldsWhenInactive() throws {
        let weekly = ProtocolSchedule(daysOfWeek: [1, 3], timesPerDay: 1, preferredTimes: ["8:00 AM"])
        let encoder = JSONEncoder()
        let data = try encoder.encode(weekly)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("intervalDays"),
                       "intervalDays should be omitted when not in interval mode to keep JSON compact")
    }
}
