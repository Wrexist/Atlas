import UIKit
import XCTest
@testable import Peptide

final class ReviewGroceryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(month: Int = 10, day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private var now: Date { date(day: 29, hour: 12) }

    private func found(printedExpiry: Date? = nil) -> FridgeScanService.Found {
        FridgeScanService.Found(
            name: "Mjölk",
            brand: nil,
            amount: nil,
            count: 1,
            place: .fridge,
            shelfDays: 5,
            printedExpiry: printedExpiry,
            pantryKey: nil,
            box: CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
            per100g: nil
        )
    }

    private func makeGrocery(printedExpiry: Date? = nil) -> ReviewGrocery {
        ReviewGrocery(found(printedExpiry: printedExpiry), sticker: UIImage(), saved: nil, now: now, calendar: calendar)
    }

    func test_moveToFreezer_guessedExpiry_isReDatedForTheFreezer() {
        var grocery = makeGrocery()
        XCTAssertEqual(grocery.expiresOn, date(month: 11, day: 3))

        grocery.move(to: .freezer, now: now, calendar: calendar)

        XCTAssertEqual(grocery.place, .freezer)
        XCTAssertEqual(grocery.expiresOn, calendar.date(byAdding: .day, value: 90, to: date(day: 29)))
    }

    func test_moveToFreezer_printedExpiry_isKept() {
        var grocery = makeGrocery(printedExpiry: date(day: 31))

        grocery.move(to: .freezer, now: now, calendar: calendar)

        XCTAssertEqual(grocery.place, .freezer)
        XCTAssertEqual(grocery.expiresOn, date(day: 31))
    }

    func test_moveToFreezer_dateSetByTheUser_isKept() {
        var grocery = makeGrocery()
        grocery.expiresOn = date(month: 11, day: 10)

        grocery.move(to: .freezer, now: now, calendar: calendar)

        XCTAssertEqual(grocery.expiresOn, date(month: 11, day: 10))
    }

    func test_moveTwice_guessedExpiry_followsEachPlace() {
        var grocery = makeGrocery()

        grocery.move(to: .freezer, now: now, calendar: calendar)
        grocery.move(to: .fridge, now: now, calendar: calendar)

        XCTAssertEqual(grocery.expiresOn, date(month: 11, day: 3))
    }
}
