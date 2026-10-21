import XCTest
@testable import Peptide

final class HealthSyncEngineTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        return c
    }()

    private func october(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)) ?? Date()
    }

    func test_dayAlreadyLoggedInAtlas_isNotImported() {
        let existing = [WeightEntry(date: october(19, 7), kg: 80)]
        let external = [WeightEntry(date: october(19, 9), kg: 79.4)]

        XCTAssertTrue(HealthSyncEngine.weightsToImport(external, existing: existing, calendar: calendar).isEmpty)
    }

    func test_severalReadingsInOneDay_importsTheLatest() {
        let morning = WeightEntry(date: october(18, 7), kg: 80.2)
        let evening = WeightEntry(date: october(18, 21), kg: 81.0)

        let imported = HealthSyncEngine.weightsToImport([evening, morning], existing: [], calendar: calendar)

        XCTAssertEqual(imported, [evening])
    }

    func test_newDays_importOldestFirst() {
        let later = WeightEntry(date: october(18, 7), kg: 80)
        let earlier = WeightEntry(date: october(16, 7), kg: 80.5)

        let imported = HealthSyncEngine.weightsToImport([later, earlier], existing: [], calendar: calendar)

        XCTAssertEqual(imported, [earlier, later])
    }

    func test_importingTwice_addsNothingTheSecondTime() {
        let external = [WeightEntry(date: october(17, 7), kg: 80)]
        let first = HealthSyncEngine.weightsToImport(external, existing: [], calendar: calendar)

        XCTAssertTrue(HealthSyncEngine.weightsToImport(external, existing: first, calendar: calendar).isEmpty)
    }

    func test_readingTheUserDeleted_isNotImportedAgain() {
        let wrongReading = WeightEntry(date: october(17, 7), kg: 120)

        let imported = HealthSyncEngine.weightsToImport(
            [wrongReading], existing: [], dismissed: [wrongReading.id], calendar: calendar
        )

        XCTAssertTrue(imported.isEmpty)
    }
}
