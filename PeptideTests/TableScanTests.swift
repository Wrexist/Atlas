import XCTest
import UIKit
@testable import Peptide

/// The whole-table scan: finding dishes in Vision's instance mask, placing
/// them on the photo card and the table, naming them from a scan, and
/// keeping a table on disk.
@MainActor
final class TableScanTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        SwiftDataRepository.shared.configureForTesting()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TableScanTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        DataStore.current = nil
        SwiftDataRepository.shared.deleteAll()
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: - Instance boxes

    func test_instanceBoxes_boundsEachLabelNormalised() {
        // 4×2 mask, padded rows: label 1 in the top-left 2×1, label 2 in
        // the bottom-right pixel.
        let width = 4, height = 2, bytesPerRow = 6
        var labels = [UInt8](repeating: 0, count: bytesPerRow * height)
        labels[0] = 1
        labels[1] = 1
        labels[bytesPerRow + 3] = 2
        // Garbage in the row padding must be ignored.
        labels[4] = 9

        let boxes = Dictionary(uniqueKeysWithValues: TableLiftEngine.instanceBoxes(
            labels: labels, width: width, height: height, bytesPerRow: bytesPerRow
        ).map { ($0.label, $0.frame) })

        XCTAssertEqual(Set(boxes.keys), [1, 2])
        XCTAssertEqual(boxes[1], CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        XCTAssertEqual(boxes[2], CGRect(x: 0.75, y: 0.5, width: 0.25, height: 0.5))
    }

    func test_instanceBoxes_emptyMask_findsNothing() {
        XCTAssertTrue(TableLiftEngine.instanceBoxes(labels: [0, 0, 0, 0], width: 2, height: 2, bytesPerRow: 2).isEmpty)
    }

    func test_dishes_dropsCrumbs_andReadsTopRowLeftToRight() {
        let boxes = [
            TableLiftEngine.Box(label: 1, frame: CGRect(x: 0.6, y: 0.6, width: 0.3, height: 0.3)),
            TableLiftEngine.Box(label: 2, frame: CGRect(x: 0.5, y: 0.05, width: 0.3, height: 0.2)),
            TableLiftEngine.Box(label: 3, frame: CGRect(x: 0.05, y: 0.02, width: 0.3, height: 0.2)),
            TableLiftEngine.Box(label: 4, frame: CGRect(x: 0.4, y: 0.4, width: 0.05, height: 0.05)),
        ]
        XCTAssertEqual(TableLiftEngine.dishes(in: boxes).map(\.label), [3, 2, 1])
    }

    func test_dishes_keepsTheLargestWhenOverTheCap() {
        let boxes = (1...12).map { index in
            TableLiftEngine.Box(label: index, frame: CGRect(x: 0, y: 0, width: 0.1 + Double(index) * 0.01, height: 0.2))
        }
        let kept = TableLiftEngine.dishes(in: boxes).map(\.label)
        XCTAssertEqual(kept.count, TableLiftEngine.maxDishes)
        XCTAssertEqual(Set(kept), Set(5...12))
    }

    // MARK: - Stage layout

    func test_aspectFill_tallPhotoInSquareCard_overflowsVerticallyCentred() {
        let rect = TableStageLayout.aspectFill(CGSize(width: 300, height: 400), in: CGSize(width: 300, height: 300))
        XCTAssertEqual(rect, CGRect(x: 0, y: -50, width: 300, height: 400))
    }

    func test_place_mapsPhotoFrameOntoCard() {
        let placed = TableStageLayout.place(
            CGRect(x: 0.5, y: 0.5, width: 0.25, height: 0.25),
            photo: CGSize(width: 300, height: 400),
            card: CGSize(width: 300, height: 300)
        )
        XCTAssertEqual(placed, CGRect(x: 150, y: 150, width: 75, height: 100))
    }

    func test_cells_fourDishes_makeTwoByTwoInsideBounds() {
        let size = CGSize(width: 400, height: 300)
        let cells = PlateTableLayout.cells(count: 4, in: size, spacing: 10)
        XCTAssertEqual(cells.count, 4)
        XCTAssertEqual(Set(cells.map(\.minY)).count, 2)
        for cell in cells {
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(cell))
            XCTAssertEqual(cell.width, cell.height)
        }
        for (index, cell) in cells.enumerated() {
            for other in cells[(index + 1)...] { XCTAssertFalse(cell.intersects(other)) }
        }
    }

    func test_cells_shortLastRow_isCentred() {
        let size = CGSize(width: 300, height: 400)
        let cells = PlateTableLayout.cells(count: 3, in: size, spacing: 10)
        XCTAssertEqual(cells[2].midX, size.width / 2, accuracy: 0.001)
    }

    func test_fit_keepsAspectInsideCell() {
        let fitted = PlateTableLayout.fit(CGSize(width: 200, height: 100), in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(fitted, CGRect(x: 0, y: 25, width: 100, height: 50))
    }

    // MARK: - Reading a dish

    func test_reading_singleItem_isNamedByTheItem() {
        let reading = TableDishReader.reading(
            insight: insight(kind: .meal, title: "Lunch"),
            items: [item("ramen", calories: 520)]
        )
        XCTAssertEqual(reading.name, "Ramen")
        XCTAssertEqual(reading.kind, .food)
        XCTAssertEqual(reading.calories, 520)
    }

    func test_reading_severalItems_isNamedByTheDishAndSumsThem() {
        let reading = TableDishReader.reading(
            insight: insight(kind: .meal, title: "Chicken karaage plate"),
            items: [item("fried chicken", calories: 400), item("cabbage", calories: 30)]
        )
        XCTAssertEqual(reading.name, "Chicken karaage plate")
        XCTAssertEqual(reading.calories, 430)

        let entry = reading.entry(id: UUID(), name: "Karaage", date: Date(), category: .dinner)
        XCTAssertEqual(entry.name, "Karaage")
        XCTAssertEqual(entry.calories, 430)
        XCTAssertEqual(entry.source, .photo)
        XCTAssertEqual(entry.components?.count, 2)
    }

    func test_reading_drinkScan_isSortedAsDrink() {
        let reading = TableDishReader.reading(insight: insight(kind: .drink, title: "Iced coffee"), items: [item("iced coffee", calories: 120)])
        XCTAssertEqual(reading.kind, .drink)
    }

    // MARK: - Keeping a table

    func test_keep_logsEveryDish_writesStickers_andSurvivesReload() async throws {
        let dataStore = DataStore(seedSampleData: false)
        let store = TableMomentStore(directory: directory)
        let date = Date()
        let dishes = ["Ramen", "Spaghetti"].map { name in
            TableMomentStore.Draft.Dish(
                entry: TableDishReader.reading(insight: insight(kind: .meal, title: name), items: [item(name, calories: 300)])
                    .entry(id: UUID(), name: name, date: date, category: .lunch),
                kind: .food,
                sticker: sticker()
            )
        }

        await store.keep(.init(date: date, category: .lunch, dishes: dishes), in: dataStore)

        XCTAssertEqual(store.progress, .init(total: 2, saved: 2, outcome: .done))
        let logged = Set(dataStore.mealEntries(for: date).map(\.id))
        XCTAssertTrue(dishes.allSatisfy { logged.contains($0.entry.id) })

        let reloaded = TableMomentStore(directory: directory)
        let moment = try XCTUnwrap(reloaded.moments.first)
        XCTAssertEqual(moment.dishes.map(\.name), ["Ramen", "Spaghetti"])
        XCTAssertEqual(moment.calories, 600)
        XCTAssertNotNil(reloaded.sticker(for: moment.dishes[0]))
    }

    func test_keep_intoExistingTable_appendsDishes() async throws {
        let dataStore = DataStore(seedSampleData: false)
        let store = TableMomentStore(directory: directory)
        let date = Date()
        await store.keep(.init(date: date, category: .dinner, dishes: [dish("Soup", date: date)]), in: dataStore)
        let id = try XCTUnwrap(store.moments.first?.id)

        await store.keep(.init(momentID: id, date: date, category: .dinner, dishes: [dish("Bread", date: date)]), in: dataStore)

        XCTAssertEqual(store.moments.count, 1)
        XCTAssertEqual(store.moments.first?.dishes.map(\.name), ["Soup", "Bread"])
    }

    func test_removeLastDish_dropsTheTable() async throws {
        let dataStore = DataStore(seedSampleData: false)
        let store = TableMomentStore(directory: directory)
        let date = Date()
        let only = dish("Salad", date: date)
        await store.keep(.init(date: date, category: .lunch, dishes: [only]), in: dataStore)
        let moment = try XCTUnwrap(store.moments.first)

        store.remove(dishID: only.entry.id, from: moment.id)

        XCTAssertTrue(store.moments.isEmpty)
        XCTAssertTrue(TableMomentStore(directory: directory).moments.isEmpty)
    }

    func test_logged_dropsDeletedDishes_andShowsDiaryEdits() {
        let kept = UUID(), deleted = UUID()
        let moment = TableMoment(date: Date(), category: .lunch, dishes: [
            TableDish(id: kept, name: "Ramen", kind: .food, calories: 500, proteinG: 20),
            TableDish(id: deleted, name: "Gyoza", kind: .food, calories: 300, proteinG: 12),
        ])
        let edited = MealEntry(id: kept, date: Date(), category: .lunch, name: "Tonkotsu ramen",
                               calories: 650, proteinG: 30, carbsG: 70, fatG: 25, source: .photo)

        let dishes = moment.logged(in: [edited])

        XCTAssertEqual(dishes.map(\.id), [kept])
        XCTAssertEqual(dishes.first?.name, "Tonkotsu ramen")
        XCTAssertEqual(dishes.first?.calories, 650)
        XCTAssertEqual(dishes.first?.proteinG, 30)
    }

    func test_removeDish_findsItsTable_andDropsTheEmptyTable() async throws {
        let dataStore = DataStore(seedSampleData: false)
        let store = TableMomentStore(directory: directory)
        let date = Date()
        let only = dish("Soup", date: date)
        await store.keep(.init(date: date, category: .dinner, dishes: [only]), in: dataStore)

        store.removeDish(id: only.entry.id)

        XCTAssertTrue(store.moments.isEmpty)
    }

    // MARK: - Fixtures

    private func insight(kind: FoodKind, title: String) -> ScanInsight {
        ScanInsight(kind: kind, title: title, summary: "", tips: [])
    }

    private func item(_ name: String, calories: Int) -> MealScannerService.ScannedFoodItem {
        MealScannerService.ScannedFoodItem(
            name: name, quantityLabel: "1 plate", grams: 300,
            calories: calories, proteinG: 20, carbsG: 40, fatG: 10, confidence: 0.9
        )
    }

    private func dish(_ name: String, date: Date) -> TableMomentStore.Draft.Dish {
        TableMomentStore.Draft.Dish(
            entry: TableDishReader.reading(insight: insight(kind: .meal, title: name), items: [item(name, calories: 200)])
                .entry(id: UUID(), name: name, date: date, category: .lunch),
            kind: .food,
            sticker: sticker()
        )
    }

    private func sticker() -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
