import XCTest
@testable import Peptide

final class FridgeScanServiceTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func response(_ items: String, isGroceries: Bool = true) -> Data {
        Data("""
        {"result": {"is_groceries": \(isGroceries), "items": [\(items)]}, "model": "claude-opus-5-5"}
        """.utf8)
    }

    private let milk = """
    {"name": "Mellanmjölk", "brand": "Arla", "amount": "1 l", "count": 2, "place": "fridge", "shelf_days": 7,
     "printed_expiry": "2026-11-03", "pantry_key": "milk", "box": {"x": 0.1, "y": 0.2, "width": 0.2, "height": 0.3},
     "kcal_100g": 46, "protein_100g": 3.5, "carbs_100g": 4.8, "fat_100g": 1.5}
    """

    func test_parse_readsEveryField() throws {
        let found = try FridgeScanService.parse(response(milk), pantryKeys: ["milk"], calendar: calendar)

        XCTAssertEqual(found.count, 1)
        let item = try XCTUnwrap(found.first)
        XCTAssertEqual(item.name, "Mellanmjölk")
        XCTAssertEqual(item.brand, "Arla")
        XCTAssertEqual(item.count, 2)
        XCTAssertEqual(item.place, .fridge)
        XCTAssertEqual(item.pantryKey, "milk")
        XCTAssertEqual(item.printedExpiry, calendar.date(from: DateComponents(year: 2026, month: 11, day: 3)))
        XCTAssertEqual(item.box.minX, 0.1, accuracy: 0.0001)
        XCTAssertEqual(item.box.minY, 0.2, accuracy: 0.0001)
        XCTAssertEqual(item.box.width, 0.2, accuracy: 0.0001)
        XCTAssertEqual(item.box.height, 0.3, accuracy: 0.0001)
        XCTAssertEqual(item.per100g?.calories, 46)
    }

    func test_parse_dropsKeysOutsideTheLibraryAndClampsBoxes() throws {
        let odd = """
        {"name": "Kombucha", "brand": null, "amount": null, "count": 0, "place": "garage", "shelf_days": null,
         "printed_expiry": "soon", "pantry_key": "kombucha", "box": {"x": 0.9, "y": 0.9, "width": 0.5, "height": 0.5},
         "kcal_100g": null, "protein_100g": null, "carbs_100g": null, "fat_100g": null}
        """
        let item = try XCTUnwrap(FridgeScanService.parse(response(odd), pantryKeys: ["milk"], calendar: calendar).first)

        XCTAssertNil(item.pantryKey)
        XCTAssertEqual(item.count, 1)
        XCTAssertEqual(item.place, .fridge)
        XCTAssertNil(item.printedExpiry)
        XCTAssertNil(item.per100g)
        XCTAssertEqual(item.box.maxX, 1, accuracy: 0.0001)
        XCTAssertEqual(item.box.maxY, 1, accuracy: 0.0001)
    }

    func test_parse_photoWithoutGroceries_throwsNoFood() throws {
        do {
            _ = try FridgeScanService.parse(response("", isGroceries: false), pantryKeys: [], calendar: calendar)
            XCTFail("expected noFoodDetected")
        } catch MealScannerService.ScanError.noFoodDetected {
            // Expected.
        }
    }

    func test_centralInstances_preferTheProductOverNeighbours() {
        let boxes = [
            TableLiftEngine.Box(label: 1, frame: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)),
            TableLiftEngine.Box(label: 2, frame: CGRect(x: 0.9, y: 0.0, width: 0.1, height: 0.1)),
        ]
        XCTAssertEqual(FridgeLiftEngine.centralInstances(boxes), IndexSet(integer: 1))
    }

    func test_day_onABuddhistCalendarPhone_readsTheISODateAsGregorian() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "UTC")!

        XCTAssertEqual(
            FridgeScanService.day(from: "2026-11-03", calendar: buddhist),
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))
        )
    }
}
