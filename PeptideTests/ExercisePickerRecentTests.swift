import XCTest
@testable import Peptide

/// The picker's Recent section: which exercise ids it surfaces from the
/// user's latest finished sessions, and in what order.
@MainActor
final class ExercisePickerRecentTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(
        _ exerciseIDs: [String],
        finishedHoursAgo: Double?
    ) -> WorkoutSession {
        WorkoutSession(
            startedAt: base.addingTimeInterval(-86_400),
            finishedAt: finishedHoursAgo.map { base.addingTimeInterval(-$0 * 3_600) },
            exercises: exerciseIDs.enumerated().map { WorkoutExerciseEntry(exerciseID: $1, index: $0) }
        )
    }

    func test_recent_newestSessionFirst_inLoggedOrder() {
        let sessions = [
            session(["Squat", "Row"], finishedHoursAgo: 48),
            session(["Bench", "Curl"], finishedHoursAgo: 1)
        ]

        XCTAssertEqual(
            ExercisePickerSheet.recentExerciseIDs(from: sessions),
            ["Bench", "Curl", "Squat", "Row"]
        )
    }

    func test_recent_followsEntryIndexNotArrayOrder() {
        let shuffled = WorkoutSession(
            finishedAt: base,
            exercises: [
                WorkoutExerciseEntry(exerciseID: "Second", index: 1),
                WorkoutExerciseEntry(exerciseID: "First", index: 0)
            ]
        )

        XCTAssertEqual(ExercisePickerSheet.recentExerciseIDs(from: [shuffled]), ["First", "Second"])
    }

    func test_recent_dedupesKeepingMostRecentPosition() {
        let sessions = [
            session(["Bench", "Squat"], finishedHoursAgo: 1),
            session(["Squat", "Deadlift"], finishedHoursAgo: 24)
        ]

        XCTAssertEqual(
            ExercisePickerSheet.recentExerciseIDs(from: sessions),
            ["Bench", "Squat", "Deadlift"]
        )
    }

    func test_recent_skipsTheActiveSession() {
        let sessions = [
            session(["InProgress"], finishedHoursAgo: nil),
            session(["Bench"], finishedHoursAgo: 2)
        ]

        XCTAssertEqual(ExercisePickerSheet.recentExerciseIDs(from: sessions), ["Bench"])
    }

    func test_recent_capsAtLimit() {
        let ids = (0..<12).map { "Lift\($0)" }

        let recent = ExercisePickerSheet.recentExerciseIDs(from: [session(ids, finishedHoursAgo: 1)])

        XCTAssertEqual(recent, Array(ids.prefix(ExercisePickerSheet.recentExerciseLimit)))
    }

    func test_recent_onlyReadsTheNewestSessions() {
        let sessions = (0..<3).map { session(["Lift\($0)"], finishedHoursAgo: Double($0)) }

        XCTAssertEqual(
            ExercisePickerSheet.recentExerciseIDs(from: sessions, sessionLimit: 2),
            ["Lift0", "Lift1"]
        )
    }

    func test_recent_noHistory_isEmpty() {
        XCTAssertEqual(ExercisePickerSheet.recentExerciseIDs(from: []), [])
    }
}
