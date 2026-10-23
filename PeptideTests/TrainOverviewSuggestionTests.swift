import XCTest
@testable import Peptide

/// The overview's two nudges: the next routine in the user's rotation and
/// the training days logged toward this week's goal.
@MainActor
final class TrainOverviewSuggestionTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Wednesday 2026-10-21 12:00 UTC.
    private let wednesday = Date(timeIntervalSince1970: 1_792_584_000)

    private func routine(_ name: String, empty: Bool = false) -> Routine {
        Routine(name: name, exercises: empty ? [] : [RoutineExercise(exerciseID: "squat", index: 0)])
    }

    private func finished(_ start: Date, routineID: UUID? = nil) -> WorkoutSession {
        WorkoutSession(routineID: routineID, startedAt: start, finishedAt: start.addingTimeInterval(3_600))
    }

    func test_suggestedRoutine_afterLastTrainedRoutine_returnsTheNextOne() {
        let push = routine("Push"), pull = routine("Pull"), legs = routine("Legs")
        let history = [
            finished(wednesday.addingTimeInterval(-86_400 * 2), routineID: push.id),
            finished(wednesday.addingTimeInterval(-86_400), routineID: pull.id),
        ]

        let next = TrainOverviewView.suggestedRoutine(from: [push, pull, legs], history: history)

        XCTAssertEqual(next?.id, legs.id)
    }

    func test_suggestedRoutine_afterLastRoutineInLibrary_wrapsToTheFirst() {
        let push = routine("Push"), pull = routine("Pull")
        let history = [finished(wednesday, routineID: pull.id)]

        let next = TrainOverviewView.suggestedRoutine(from: [push, pull], history: history)

        XCTAssertEqual(next?.id, push.id)
    }

    func test_suggestedRoutine_withNoRoutineHistory_returnsTheFirstStartableRoutine() {
        let draft = routine("Draft", empty: true), push = routine("Push")

        let next = TrainOverviewView.suggestedRoutine(from: [draft, push], history: [finished(wednesday)])

        XCTAssertEqual(next?.id, push.id)
    }

    func test_suggestedRoutine_withOnlyEmptyRoutines_returnsNil() {
        XCTAssertNil(TrainOverviewView.suggestedRoutine(from: [routine("Draft", empty: true)], history: []))
    }

    func test_trainedDaysThisWeek_twoSessionsOneDay_countsTheDayOnce() {
        let sessions = [
            finished(wednesday),
            finished(wednesday.addingTimeInterval(3_600 * 3)),
            finished(wednesday.addingTimeInterval(-86_400)),
        ]

        let days = TrainOverviewView.trainedDaysThisWeek(sessions, now: wednesday, calendar: calendar)

        XCTAssertEqual(days, 2)
    }

    func test_trainedDaysThisWeek_lastWeekAndInProgress_areLeftOut() {
        let lastSunday = wednesday.addingTimeInterval(-86_400 * 3)
        let inProgress = WorkoutSession(startedAt: wednesday)

        let days = TrainOverviewView.trainedDaysThisWeek([finished(lastSunday), inProgress], now: wednesday, calendar: calendar)

        XCTAssertEqual(days, 0)
    }
}
