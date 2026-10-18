import XCTest
@testable import Peptide

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
final class DoseWindowStatusTests: XCTestCase {

    private func makeState(
        doseTime: Date,
        windowStart: Date? = nil,
        completed: Bool = false,
        loggedAt: Date? = nil
    ) -> DoseWindowAttributes.ContentState {
        DoseWindowAttributes.ContentState(
            doseTime: doseTime,
            windowStart: windowStart ?? doseTime.addingTimeInterval(-30 * 60),
            completed: completed,
            loggedAt: loggedAt
        )
    }

    // MARK: - Status state machine

    func test_status_completed_takesPriorityOverTime() {
        let now = Date()
        let state = makeState(doseTime: now.addingTimeInterval(-3600), completed: true)
        XCTAssertEqual(state.status(at: now), .completed)
    }

    func test_status_upcoming_fortyMinutesOut_reportsMinutes() {
        let now = Date()
        let state = makeState(doseTime: now.addingTimeInterval(40 * 60))
        XCTAssertEqual(state.status(at: now), .upcoming(minutesUntil: 40))
    }

    func test_status_dueNow_threeMinutesBefore() {
        let now = Date()
        let state = makeState(doseTime: now.addingTimeInterval(3 * 60))
        XCTAssertEqual(state.status(at: now), .dueNow)
    }

    func test_status_dueNow_threeMinutesAfter() {
        let now = Date()
        let state = makeState(doseTime: now.addingTimeInterval(-3 * 60))
        XCTAssertEqual(state.status(at: now), .dueNow)
    }

    func test_status_late_sevenMinutesAfter_reportsMinutes() {
        let now = Date()
        let state = makeState(doseTime: now.addingTimeInterval(-7 * 60))
        XCTAssertEqual(state.status(at: now), .late(minutes: 7))
    }

    // MARK: - Window interval

    func test_windowInterval_spansWindowStartToDoseTime() {
        let doseTime = Date()
        let windowStart = doseTime.addingTimeInterval(-30 * 60)
        let state = makeState(doseTime: doseTime, windowStart: windowStart)
        XCTAssertEqual(state.windowInterval, windowStart...doseTime)
    }

    func test_windowInterval_windowStartAfterDoseTime_collapsesInsteadOfInverting() {
        let doseTime = Date()
        let state = makeState(doseTime: doseTime, windowStart: doseTime.addingTimeInterval(60))
        XCTAssertEqual(state.windowInterval, doseTime...doseTime)
    }
}
#endif
