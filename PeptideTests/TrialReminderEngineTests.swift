import XCTest
@testable import Peptide

final class TrialReminderEngineTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    func test_sevenDayTrial_firesTwoDaysBeforeTrialEnd() {
        let fire = TrialReminderEngine.fireDate(trialEnd: date(8), now: date(1), calendar: calendar)
        XCTAssertEqual(fire, date(6))
    }

    func test_trialEndingInUnderTwoDays_isSkipped() {
        let fire = TrialReminderEngine.fireDate(trialEnd: date(8), now: date(6, hour: 13), calendar: calendar)
        XCTAssertNil(fire)
    }

    func test_trialEndingExactlyTwoDaysOut_isSkipped() {
        let fire = TrialReminderEngine.fireDate(trialEnd: date(8), now: date(6), calendar: calendar)
        XCTAssertNil(fire)
    }

    func test_alreadyEndedTrial_isSkipped() {
        let fire = TrialReminderEngine.fireDate(trialEnd: date(1), now: date(8), calendar: calendar)
        XCTAssertNil(fire)
    }

    func test_body_quotesPriceAndChargeDate() {
        let body = TrialReminderEngine.body(
            price: "€9,99",
            chargeDate: date(8),
            locale: Locale(identifier: "en_US")
        )
        XCTAssertTrue(body.hasPrefix("Your Atlas Pro trial ends in 2 days"))
        XCTAssertTrue(body.contains("€9,99"))
        XCTAssertTrue(body.contains("Mar"))
        XCTAssertTrue(body.hasSuffix("unless you cancel in Settings."))
    }
}
