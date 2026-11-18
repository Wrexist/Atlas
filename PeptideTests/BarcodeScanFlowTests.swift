import XCTest
@testable import Peptide

final class BarcodeScanFlowTests: XCTestCase {

    private let now: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 12))!
    }()

    func test_freshLookup_hidesDataAge() {
        XCTAssertFalse(BarcodeScanFlow.showsDataAge(fetchedAt: now.addingTimeInterval(-2), now: now))
        XCTAssertFalse(BarcodeScanFlow.showsDataAge(fetchedAt: now.addingTimeInterval(-86_000), now: now))
    }

    func test_cachedLookupOlderThanADay_showsDataAge() {
        XCTAssertTrue(BarcodeScanFlow.showsDataAge(fetchedAt: now.addingTimeInterval(-3 * 86_400), now: now))
    }
}
