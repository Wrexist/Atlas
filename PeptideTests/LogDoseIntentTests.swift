import XCTest
@testable import Peptide

/// Pins the write behind "Log my [peptide] dose" — the Siri, Shortcuts
/// and Action Button path that runs without the app on screen.
@MainActor
final class LogDoseIntentTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SwiftDataRepository.shared.configureForTesting()
    }

    override func tearDown() {
        // Release the store so a debounced save can't land in the next
        // test's container (see LifestyleDataStoreTests.tearDown).
        DataStore.current = nil
        SwiftDataRepository.shared.deleteAll()
        super.tearDown()
    }

    private let peptideID = MockPeptides.bpc157.id.uuidString

    /// A store with one active protocol and a dose today at each of
    /// `hours` past midnight, logged where `completed` says so.
    private func makeStore(hours: [Int], completed: Set<Int> = []) -> DataStore {
        let store = DataStore(seedSampleData: false)
        let proto = PeptideProtocol(
            id: UUID(),
            name: "Test",
            peptides: [MockPeptides.bpc157],
            schedule: ProtocolSchedule(
                daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
                timesPerDay: 1,
                preferredTimes: ["8:00 AM"]
            ),
            cycleLengthWeeks: 8,
            startDate: Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
            status: .active,
            notes: ""
        )
        store.protocols.append(proto)
        let midnight = Calendar.current.startOfDay(for: Date())
        store.entries.append(contentsOf: hours.map { hour in
            ProtocolEntry(
                id: UUID(),
                protocolId: proto.id,
                peptide: MockPeptides.bpc157,
                date: midnight.addingTimeInterval(TimeInterval(hour * 3600)),
                dose: "\(hour)00mcg",
                notes: "",
                completed: completed.contains(hour)
            )
        })
        return store
    }

    func test_logEarliestDose_twoPending_logsTheEarlierOne() {
        let store = makeStore(hours: [20, 8])

        let result = LogDoseIntent.logEarliestDose(of: peptideID, in: store)

        let morning = store.todayEntries.first { $0.dose == "800mcg" }
        let evening = store.todayEntries.first { $0.dose == "2000mcg" }
        guard case .logged(_, let dose) = result else {
            return XCTFail("Expected the morning dose to be logged")
        }
        XCTAssertEqual(dose, "800mcg")
        XCTAssertEqual(morning?.completed, true)
        XCTAssertEqual(evening?.completed, false)
    }

    func test_logEarliestDose_earlierAlreadyLogged_logsTheNextOne() {
        let store = makeStore(hours: [8, 20], completed: [8])

        let result = LogDoseIntent.logEarliestDose(of: peptideID, in: store)

        guard case .logged(_, let dose) = result else {
            return XCTFail("Expected the evening dose to be logged")
        }
        XCTAssertEqual(dose, "2000mcg")
    }

    func test_logEarliestDose_stampsAndReportsTheTimeItWasLogged() {
        let store = makeStore(hours: [8])
        let loggedAt = Calendar.current.startOfDay(for: Date()).addingTimeInterval(10 * 3600 + 40 * 60)

        let result = LogDoseIntent.logEarliestDose(of: peptideID, in: store, at: loggedAt)

        XCTAssertEqual(result, .logged(at: loggedAt, dose: "800mcg"))
        XCTAssertEqual(store.todayEntries.first?.actualTime, loggedAt)
    }

    func test_logEarliestDose_allLogged_reportsNothingToLog() {
        let store = makeStore(hours: [8], completed: [8])

        XCTAssertEqual(LogDoseIntent.logEarliestDose(of: peptideID, in: store), .nothingToLog)
    }

    func test_logEarliestDose_unknownPeptide_reportsNothingToLogAndWritesNothing() {
        let store = makeStore(hours: [8])

        let result = LogDoseIntent.logEarliestDose(of: UUID().uuidString, in: store)

        XCTAssertEqual(result, .nothingToLog)
        XCTAssertFalse(store.todayEntries.contains(where: \.completed))
    }

    func test_logEarliestDose_flushesTheWriteToDisk() {
        let store = makeStore(hours: [8])

        _ = LogDoseIntent.logEarliestDose(of: peptideID, in: store)

        let saved = SwiftDataRepository.shared.loadEntries()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.completed, true)
    }
}
