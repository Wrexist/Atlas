import XCTest
@testable import Peptide

/// Pins the protocol half of the widget payload: which of today's doses
/// reach the Medium widget's three-row list.
final class WidgetSnapshotProtocolTests: XCTestCase {

    private let morning = Date(timeIntervalSince1970: 1_749_628_800)

    private func entry(hour: Int, completed: Bool) -> ProtocolEntry {
        ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: MockPeptides.bpc157,
            date: morning.addingTimeInterval(TimeInterval(hour * 3600)),
            dose: "250mcg",
            notes: "",
            completed: completed
        )
    }

    func test_upcoming_firstThreeDosesLogged_listsPendingDosesFirst() {
        let today = [
            entry(hour: 0, completed: true),
            entry(hour: 1, completed: true),
            entry(hour: 2, completed: true),
            entry(hour: 3, completed: false),
            entry(hour: 4, completed: false),
        ]

        let data = WidgetSnapshotBuilder.build(today: today, now: morning)

        XCTAssertEqual(data.upcoming.map(\.completed), [false, false, true])
        XCTAssertEqual(data.upcoming.map(\.time), [today[3].date, today[4].date, today[2].date])
    }

    func test_upcoming_unsortedInput_keepsPendingDosesChronological() {
        let today = [
            entry(hour: 5, completed: false),
            entry(hour: 2, completed: false),
        ]

        let data = WidgetSnapshotBuilder.build(today: today, now: morning)

        XCTAssertEqual(data.upcoming.map(\.time), [today[1].date, today[0].date])
    }

    /// A missed dose stays the hero until it's logged, even after a later
    /// dose is: the Watch complication picks the same one, and the
    /// widget's overdue flag keys off it.
    func test_build_missedDoseThenLaterDoseLogged_nextIsTheMissedDose() {
        let today = [
            entry(hour: 8, completed: false),
            entry(hour: 9, completed: true),
            entry(hour: 20, completed: false),
        ]

        let data = WidgetSnapshotBuilder.build(today: today, now: morning.addingTimeInterval(10 * 3600))

        XCTAssertEqual(data.nextDoseTime, today[0].date)
    }

    func test_build_allDosesLogged_hasNoNextDose() {
        let today = [entry(hour: 8, completed: true)]

        let data = WidgetSnapshotBuilder.build(today: today, now: morning)

        XCTAssertNil(data.nextDoseTime)
        XCTAssertEqual(data.nextPeptideName, "")
    }

    /// A three-times-a-week protocol on a rest day: nothing due today,
    /// but the widget must still know a protocol is running.
    func test_build_activeProtocolWithNoDosesToday_reportsActiveProtocolAndNoDoses() {
        let data = WidgetSnapshotBuilder.build(today: [], hasActiveProtocol: true, now: morning)

        XCTAssertTrue(data.hasActiveProtocol)
        XCTAssertEqual(data.totalToday, 0)
        XCTAssertNil(data.nextDoseTime)
    }
}
