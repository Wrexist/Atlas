import XCTest
@testable import Peptide

@MainActor
final class FridgeStoreTests: XCTestCase {
    private var directory: URL!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(day: Int = 29, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("FridgeStoreTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func test_add_savesTheProductAndSurvivesARelaunch() {
        let store = FridgeStore(directory: directory)
        store.add(FridgeProduct(name: "Mjölk", pantryKey: "milk"), count: 2, expiresOn: date(day: 5), now: date(), calendar: calendar)

        let reopened = FridgeStore(directory: directory)

        XCTAssertEqual(reopened.items.count, 1)
        XCTAssertEqual(reopened.items.first?.count, 2)
        XCTAssertEqual(reopened.products.first?.name, "Mjölk")
    }

    func test_reAddingTheSameProduct_reusesTheSavedOneAndLearnsItsShelfLife() {
        let store = FridgeStore(directory: directory)
        store.add(FridgeProduct(name: "Mjölk", brand: "Arla"), expiresOn: date(day: 31, hour: 0), now: date(day: 24), calendar: calendar)
        store.add(FridgeProduct(name: "mjölk", brand: "arla"), expiresOn: date(day: 31, hour: 0), now: date(day: 29), calendar: calendar)

        XCTAssertEqual(store.products.count, 1)
        XCTAssertEqual(store.products.first?.shelfDays, 2)
        XCTAssertEqual(store.items.count, 1, "same product, same day, same place stacks")
        XCTAssertEqual(store.items.first?.count, 2)
    }

    func test_barcode_identifiesAProductOverItsName() {
        let store = FridgeStore(directory: directory)
        store.add(FridgeProduct(name: "Yoghurt", barcode: "7310865004703"), now: date(), calendar: calendar)
        store.add(FridgeProduct(name: "Yoghurt", barcode: "7310865000000"), now: date(), calendar: calendar)

        XCTAssertEqual(store.products.count, 2)
    }

    func test_useOne_decrementsThenRemovesButKeepsTheProductSaved() {
        let store = FridgeStore(directory: directory)
        let item = store.add(FridgeProduct(name: "Ägg"), count: 2, now: date(), calendar: calendar)

        store.useOne(item.id)
        XCTAssertEqual(store.items.first?.count, 1)
        store.useOne(item.id)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.products.count, 1)
    }

    func test_forget_dropsTheProductAndWhatIsLeftOfIt() {
        let store = FridgeStore(directory: directory)
        let item = store.add(FridgeProduct(name: "Ost"), now: date(), calendar: calendar)

        store.forget(item.productID)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.products.isEmpty)
    }

    func test_deleteAll_leavesNothingOnDisk() {
        let store = FridgeStore(directory: directory)
        store.add(FridgeProduct(name: "Smör"), photo: UIImage(systemName: "star"), now: date(), calendar: calendar)

        store.deleteAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(FridgeStore(directory: directory).products.isEmpty)
    }

    func test_pantry_countsTheFridgeAsAtHomeWithoutATick() {
        let defaults = UserDefaults(suiteName: "FridgeStoreTests.pantry")!
        defaults.removePersistentDomain(forName: "FridgeStoreTests.pantry")
        let pantry = PantryStore(defaults: defaults, fridgeKeys: { ["milk"] })

        pantry.toggle("milk")

        XCTAssertTrue(pantry.has("milk"))
        XCTAssertTrue(pantry.isInFridge("milk"))
        XCTAssertTrue(pantry.manualKeys.isEmpty, "a fridge-held ingredient isn't ticked by hand")
    }
}
