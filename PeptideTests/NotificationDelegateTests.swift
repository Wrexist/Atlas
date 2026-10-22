import XCTest
@testable import Peptide

@MainActor
final class NotificationDelegateTests: XCTestCase {

    private let protocolId = UUID()
    private let calendar = Calendar.current

    private func date(daysAgo: Int, hour: Int, minute: Int, from now: Date) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func entry(_ peptide: Peptide, at date: Date, protocolId: UUID? = nil, completed: Bool = false) -> ProtocolEntry {
        ProtocolEntry(
            id: UUID(),
            protocolId: protocolId ?? self.protocolId,
            peptide: peptide,
            date: date,
            dose: "250mcg",
            notes: "",
            completed: completed
        )
    }

    func test_entriesDue_combinedReminder_returnsEveryPeptideInTheSlot() {
        let now = calendar.date(bySettingHour: 8, minute: 5, second: 0, of: Date())!
        let slot = date(daysAgo: 0, hour: 8, minute: 0, from: now)
        let bpc = entry(MockPeptides.bpc157, at: slot)
        let tb = entry(MockPeptides.tb500, at: slot)
        let otherProtocol = entry(MockPeptides.semax, at: slot, protocolId: UUID())
        let alreadyTaken = entry(MockPeptides.ghkCu, at: slot, completed: true)

        let due = NotificationDelegate.entriesDue(
            in: [bpc, tb, otherProtocol, alreadyTaken],
            protocolId: protocolId,
            hour: 8,
            minute: 0,
            now: now
        )

        XCTAssertEqual(Set(due.map(\.id)), [bpc.id, tb.id])
    }

    func test_entriesDue_todaysSlotStillAhead_returnsYesterdaysDose() {
        let now = calendar.date(bySettingHour: 20, minute: 30, second: 0, of: Date())!
        let yesterday = entry(MockPeptides.bpc157, at: date(daysAgo: 1, hour: 20, minute: 45, from: now))
        let today = entry(MockPeptides.bpc157, at: date(daysAgo: 0, hour: 20, minute: 45, from: now))

        let due = NotificationDelegate.entriesDue(
            in: [yesterday, today],
            protocolId: protocolId,
            hour: 20,
            minute: 45,
            now: now
        )

        XCTAssertEqual(due.map(\.id), [yesterday.id])
    }

    func test_entriesDue_todaysSlotPassed_returnsTodaysDose() {
        let now = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: Date())!
        let yesterday = entry(MockPeptides.bpc157, at: date(daysAgo: 1, hour: 20, minute: 45, from: now))
        let today = entry(MockPeptides.bpc157, at: date(daysAgo: 0, hour: 20, minute: 45, from: now))

        let due = NotificationDelegate.entriesDue(
            in: [yesterday, today],
            protocolId: protocolId,
            hour: 20,
            minute: 45,
            now: now
        )

        XCTAssertEqual(due.map(\.id), [today.id])
    }

    func test_entriesDue_noMatchingSlot_returnsEmpty() {
        let now = Date()
        let other = entry(MockPeptides.bpc157, at: date(daysAgo: 0, hour: 9, minute: 15, from: now))

        let due = NotificationDelegate.entriesDue(
            in: [other],
            protocolId: protocolId,
            hour: 8,
            minute: 0,
            now: now
        )

        XCTAssertTrue(due.isEmpty)
    }
}
