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

    // MARK: - Window progress

    func test_windowProgress_zeroAtWindowStart() {
        let doseTime = Date()
        let windowStart = doseTime.addingTimeInterval(-30 * 60)
        let state = makeState(doseTime: doseTime, windowStart: windowStart)
        XCTAssertEqual(state.windowProgress(at: windowStart), 0.0, accuracy: 0.0001)
    }

    func test_windowProgress_halfwayThroughWindow() {
        let doseTime = Date()
        let windowStart = doseTime.addingTimeInterval(-30 * 60)
        let halfway = doseTime.addingTimeInterval(-15 * 60)
        let state = makeState(doseTime: doseTime, windowStart: windowStart)
        XCTAssertEqual(state.windowProgress(at: halfway), 0.5, accuracy: 0.01)
    }

    func test_windowProgress_clamped_pastDoseTime() {
        let doseTime = Date()
        let later = doseTime.addingTimeInterval(60 * 60)
        let state = makeState(doseTime: doseTime)
        XCTAssertEqual(state.windowProgress(at: later), 1.0, accuracy: 0.0001)
    }

    func test_windowProgress_completed_always1() {
        let state = makeState(doseTime: Date(), completed: true)
        XCTAssertEqual(state.windowProgress(at: Date.distantPast), 1.0)
    }
}
#endif
