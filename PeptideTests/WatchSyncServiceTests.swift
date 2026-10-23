import XCTest
@testable import Peptide

/// Pins the phone side of the Watch sync: which doses are published, in
/// what order, when a push is skipped, and how Watch commands are applied.
@MainActor
final class WatchSyncServiceTests: XCTestCase {

    private var service: WatchSyncService { .shared }
    private var savedOnLogWater: ((Double, Date) -> Void)?
    private var savedOnMarkIncomplete: ((UUID, UUID) -> Void)?

    override func setUp() {
        super.setUp()
        savedOnLogWater = service.onLogWater
        savedOnMarkIncomplete = service.onMarkIncomplete
    }

    override func tearDown() {
        service.onLogWater = savedOnLogWater
        service.onMarkIncomplete = savedOnMarkIncomplete
        super.tearDown()
    }

    private func makeProtocol(status: ProtocolStatus) -> PeptideProtocol {
        PeptideProtocol(
            id: UUID(),
            name: "Test",
            peptides: [MockPeptides.bpc157],
            schedule: ProtocolSchedule(daysOfWeek: Array(1...7), timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: 8,
            startDate: Date(),
            status: status,
            notes: ""
        )
    }

    private func entry(for proto: PeptideProtocol, at date: Date = Date(), completed: Bool = false) -> ProtocolEntry {
        ProtocolEntry(
            id: UUID(),
            protocolId: proto.id,
            peptide: MockPeptides.bpc157,
            date: date,
            dose: "250mcg",
            notes: "",
            completed: completed
        )
    }

    // MARK: - Published doses

    func test_updateWatchData_pausedProtocolEntry_isNotPublished() {
        let active = makeProtocol(status: .active)
        let paused = makeProtocol(status: .paused)
        let due = entry(for: active)

        service.updateWatchData(entries: [due, entry(for: paused)], protocols: [active, paused])

        let published = service.lastPublishedForTesting
        XCTAssertEqual(published?.todayEntries.map(\.id), [due.id])
        XCTAssertEqual(published?.totalToday, 1)
    }

    func test_todayWatchEntries_completedProtocolAndOtherDays_areLeftOut() {
        let active = makeProtocol(status: .active)
        let completed = makeProtocol(status: .completed)
        let now = Date()
        let today = entry(for: active, at: now)
        let entries = [
            today,
            entry(for: active, at: now.addingTimeInterval(-2 * 24 * 3600)),
            entry(for: completed, at: now),
        ]

        let published = WatchSyncService.todayWatchEntries(from: entries, protocols: [active, completed], now: now)

        XCTAssertEqual(published.map(\.id), [today.id])
    }

    func test_todayWatchEntries_sortsIncompleteFirstThenByTime() {
        let proto = makeProtocol(status: .active)
        let morning = Calendar.current.startOfDay(for: Date()).addingTimeInterval(8 * 3600)
        let takenEarly = entry(for: proto, at: morning, completed: true)
        let dueLate = entry(for: proto, at: morning.addingTimeInterval(4 * 3600))
        let dueEarly = entry(for: proto, at: morning.addingTimeInterval(3600))

        let published = WatchSyncService.todayWatchEntries(
            from: [takenEarly, dueLate, dueEarly], protocols: [proto], now: morning
        )

        XCTAssertEqual(published.map(\.id), [dueEarly.id, dueLate.id, takenEarly.id])
    }

    // MARK: - Skipped pushes

    func test_updateWatchData_identicalSnapshotTwice_publishesOnce() {
        service.updateWatchData(entries: [], protocols: [], atlasScore: 4_242)
        let baseline = service.publishCountForTesting

        service.updateWatchData(entries: [], protocols: [], atlasScore: 4_242)

        XCTAssertEqual(service.publishCountForTesting, baseline,
                       "A snapshot the Watch already has must not be pushed again")
    }

    /// The Watch shows its guess at once and only a push replaces it, so
    /// an undo the phone ignored must still be answered.
    func test_noOpWatchCommand_stillPublishesTheNextSnapshot() {
        service.onMarkIncomplete = { _, _ in }
        service.updateWatchData(entries: [], protocols: [], atlasScore: 4_343)
        let baseline = service.publishCountForTesting

        service.handleWatchMessage(action: WatchMessage.markIncomplete, entryId: UUID(), protocolId: UUID(),
                                   issuedAt: nil, messageID: UUID().uuidString)
        service.updateWatchData(entries: [], protocols: [], atlasScore: 4_343)

        XCTAssertEqual(service.publishCountForTesting, baseline + 1)
    }

    // MARK: - Watch commands

    func test_duplicateMessageId_isAppliedOnce() {
        var logged = 0
        service.onLogWater = { _, _ in logged += 1 }
        let id = UUID().uuidString

        service.handleWaterMessage(fluidOunces: 8, issuedAt: nil, messageID: id)
        service.handleWaterMessage(fluidOunces: 8, issuedAt: nil, messageID: id)

        XCTAssertEqual(logged, 1)
    }

    func test_futureIssuedAt_isClampedToNow() throws {
        var loggedAt: Date?
        service.onLogWater = { _, date in loggedAt = date }

        service.handleWaterMessage(fluidOunces: 8, issuedAt: Date().addingTimeInterval(3600),
                                   messageID: UUID().uuidString)

        XCTAssertLessThanOrEqual(try XCTUnwrap(loggedAt), Date())
    }
}
