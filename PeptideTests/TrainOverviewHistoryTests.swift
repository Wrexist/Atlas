import XCTest
@testable import Peptide

/// The overview's session sources: the all-time maps must see every
/// finished workout, and none of them may count the one in progress.
@MainActor
final class TrainOverviewHistoryTests: XCTestCase {

    private var repo: SwiftDataRepository { .shared }

    override func setUp() {
        super.setUp()
        repo.configureForTesting()
    }

    override func tearDown() {
        repo.deleteAll()
        super.tearDown()
    }

    private func finished(daysAgo: Int) -> WorkoutSession {
        let start = Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(-Double(daysAgo) * 86_400)
        return WorkoutSession(startedAt: start, finishedAt: start.addingTimeInterval(3_600))
    }

    func test_finishedHistory_beyondTheFetchCap_keepsEveryFinishedSession() {
        for day in 0..<250 { repo.upsertWorkoutSession(finished(daysAgo: day)) }

        let history = TrainOverviewView.finishedHistory(repo.loadAllWorkoutSessions())

        XCTAssertEqual(history.count, 250)
        XCTAssertGreaterThan(history.count, SwiftDataRepository.workoutHistoryFetchLimit)
    }

    func test_finishedHistory_withWorkoutInProgress_leavesItOutNewestFirst() {
        let older = finished(daysAgo: 2)
        let newer = finished(daysAgo: 1)
        let active = WorkoutSession(startedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let history = TrainOverviewView.finishedHistory([older, active, newer])

        XCTAssertEqual(history.map(\.id), [newer.id, older.id])
    }
}
