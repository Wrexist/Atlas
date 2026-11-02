import XCTest
@testable import Peptide

/// Pins the arithmetic the fasting Live Activity and widget draw from,
/// the activity's state machine, the fast → snapshot mapping and the
/// snapshot's wire format. All of it renders on surfaces with nothing
/// else to catch a drift: the lock screen, the Dynamic Island and a
/// widget the app never sees.
final class FastingLiveActivityTests: XCTestCase {

    private let stockholm: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        stockholm.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private var start: Date { date(2026, 10, 20, 20) }

    private func window(hours: Double = 16) -> FastingWindow {
        FastingWindow(startedAt: start, targetEnd: start.addingTimeInterval(hours * 3600))
    }

    private func hours(_ h: Double) -> Date { start.addingTimeInterval(h * 3600) }

    // MARK: - Progress and remaining time

    func test_progress_halfwayToGoal_isOneHalf() {
        XCTAssertEqual(window().progress(at: hours(8)), 0.5, accuracy: 1e-9)
    }

    func test_progress_beforeStart_isZero() {
        XCTAssertEqual(window().progress(at: hours(-1)), 0)
    }

    func test_progress_pastGoal_isClampedToOne() {
        XCTAssertEqual(window().progress(at: hours(20)), 1)
    }

    func test_progress_zeroLengthGoal_isComplete() {
        XCTAssertEqual(window(hours: 0).progress(at: start), 1)
    }

    func test_remaining_midFast_isTimeToGoal() {
        XCTAssertEqual(window().remaining(at: hours(12.5)), 3.5 * 3600, accuracy: 1e-6)
    }

    func test_remaining_pastGoal_isZero() {
        XCTAssertEqual(window().remaining(at: hours(17)), 0)
    }

    func test_elapsed_spanningDSTChange_countsRealSeconds() {
        // Clocks go back at 03:00 on 25 Oct 2026 in Stockholm: 20:00 to
        // 12:00 the next day is 17 real hours, not 16.
        let dstStart = date(2026, 10, 24, 20)
        let fast = FastingWindow(startedAt: dstStart, targetEnd: dstStart.addingTimeInterval(16 * 3600))
        XCTAssertEqual(fast.elapsed(at: date(2026, 10, 25, 12)), 17 * 3600)
        XCTAssertTrue(fast.isGoalReached(at: date(2026, 10, 25, 12)))
    }

    // MARK: - Goal reached

    func test_isGoalReached_exactlyAtTarget_isTrue() {
        XCTAssertFalse(window().isGoalReached(at: hours(15.99)))
        XCTAssertTrue(window().isGoalReached(at: hours(16)))
    }

    func test_countdownInterval_pastGoal_collapsesOntoTargetInsteadOfInverting() {
        let interval = window().countdownInterval(from: hours(18))
        XCTAssertEqual(interval.lowerBound, hours(16))
        XCTAssertEqual(interval.upperBound, hours(16))
    }

    func test_countdownInterval_midFast_runsFromNowToTarget() {
        let interval = window().countdownInterval(from: hours(10))
        XCTAssertEqual(interval.lowerBound, hours(10))
        XCTAssertEqual(interval.upperBound, hours(16))
    }

    func test_goalInterval_targetBeforeStart_doesNotInvertTheRange() {
        let malformed = FastingWindow(startedAt: start, targetEnd: hours(-2))
        XCTAssertEqual(malformed.goalInterval.lowerBound, start)
        XCTAssertEqual(malformed.goalInterval.upperBound, start)
        XCTAssertEqual(malformed.targetDuration, 0)
    }

    // MARK: - Widget timeline

    func test_timelineDates_goalWithinSpan_includesGoalInOrder() {
        let dates = window().timelineDates(from: hours(15.1), step: 15 * 60, count: 8)
        XCTAssertTrue(dates.contains(hours(16)))
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(dates.first, hours(15.1))
        XCTAssertEqual(dates.count, 9)
    }

    func test_timelineDates_goalOnAStep_isNotDuplicated() {
        let dates = window().timelineDates(from: hours(15), step: 15 * 60, count: 8)
        XCTAssertEqual(dates.filter { $0 == hours(16) }.count, 1)
        XCTAssertEqual(dates.count, 8)
    }

    func test_timelineDates_goalBeyondSpan_isEvenSteps() {
        let dates = window().timelineDates(from: hours(1), step: 15 * 60, count: 4)
        XCTAssertEqual(dates, [hours(1), hours(1.25), hours(1.5), hours(1.75)])
    }

    func test_timelineDates_pastGoal_keepsSteppingWithoutGoalEntry() {
        let dates = window().timelineDates(from: hours(18), step: 15 * 60, count: 3)
        XCTAssertEqual(dates, [hours(18), hours(18.25), hours(18.5)])
    }

    // MARK: - Snapshot

    @MainActor
    func test_snapshot_noFast_isNotFasting() {
        XCTAssertEqual(FastingWidgetPublisher.snapshot(for: nil), .notFasting)
    }

    @MainActor
    func test_snapshot_endedFast_isNotFasting() {
        let ended = FastSession(startedAt: start, endedAt: hours(16), targetHours: 16, plan: .sixteen)
        XCTAssertEqual(FastingWidgetPublisher.snapshot(for: ended), .notFasting)
    }

    @MainActor
    func test_snapshot_activeFast_carriesWindowAndProtocol() {
        let fast = FastSession(startedAt: start, targetHours: 18, plan: .eighteen)
        let active = FastingWidgetPublisher.snapshot(for: fast).active
        XCTAssertEqual(active?.fastId, fast.id)
        XCTAssertEqual(active?.window, FastingWindow(startedAt: start, targetEnd: hours(18)))
        XCTAssertEqual(active?.protocolName, "18:6")
    }

    @MainActor
    func test_protocolName_customFast_namesItsLength() {
        let fast = FastSession(startedAt: start, targetHours: 20, plan: .custom)
        XCTAssertTrue(FastingLiveActivityService.protocolName(for: fast).contains("20"))
    }

    func test_snapshot_encodeDecode_roundTrips() throws {
        let snapshot = FastingWidgetSnapshot(active: .init(
            fastId: UUID(),
            window: window(),
            protocolName: "16:8"
        ))
        XCTAssertEqual(try FastingWidgetSnapshot.decoded(from: snapshot.encoded()), snapshot)
        XCTAssertEqual(try FastingWidgetSnapshot.decoded(from: FastingWidgetSnapshot.notFasting.encoded()), .notFasting)
    }

    func test_snapshot_encodesDatesAsISO8601() throws {
        let json = try XCTUnwrap(String(data: FastingWidgetSnapshot(active: .init(
            fastId: UUID(),
            window: window(),
            protocolName: "16:8"
        )).encoded(), encoding: .utf8))
        // 20:00 Stockholm summer time is 18:00 UTC.
        XCTAssertTrue(json.contains("2026-10-20T18:00:00Z"), json)
    }

    // MARK: - End fast inbox

    func test_pendingFastEnd_drain_returnsTapsOldestFirstAndClears() {
        let suite = "FastingLiveActivityTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        PendingFastEndStore.enqueue(.init(fastId: id, endedAt: hours(17)), defaults: defaults)
        PendingFastEndStore.enqueue(.init(fastId: id, endedAt: hours(16)), defaults: defaults)

        XCTAssertEqual(PendingFastEndStore.drain(defaults: defaults).map(\.endedAt), [hours(16), hours(17)])
        XCTAssertTrue(PendingFastEndStore.drain(defaults: defaults).isEmpty)
    }
}

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
final class FastingActivityStatusTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_792_000_000)

    private func state(endedAt: Date? = nil) -> FastingActivityAttributes.ContentState {
        FastingActivityAttributes.ContentState(
            startedAt: start,
            targetEnd: start.addingTimeInterval(16 * 3600),
            endedAt: endedAt
        )
    }

    func test_status_beforeGoal_isFasting() {
        XCTAssertEqual(state().status(at: start.addingTimeInterval(3600)), .fasting)
    }

    func test_status_targetPassed_isGoalReached() {
        XCTAssertEqual(state().status(at: start.addingTimeInterval(16 * 3600)), .goalReached)
        XCTAssertEqual(state().status(at: start.addingTimeInterval(30 * 3600)), .goalReached)
    }

    func test_status_ended_beatsGoalReached() {
        let ended = state(endedAt: start.addingTimeInterval(20 * 3600))
        XCTAssertEqual(ended.status(at: start.addingTimeInterval(21 * 3600)), .ended)
    }

    func test_staleDate_isGoalWhileAhead_andNilAfter() {
        XCTAssertEqual(state().staleDate(now: start), start.addingTimeInterval(16 * 3600))
        XCTAssertNil(state().staleDate(now: start.addingTimeInterval(17 * 3600)))
    }

    @MainActor
    func test_stateForFast_mirrorsStartGoalAndEnd() {
        let fast = FastSession(startedAt: start, endedAt: start.addingTimeInterval(14 * 3600), targetHours: 16, plan: .sixteen)
        XCTAssertEqual(FastingLiveActivityService.state(for: fast), state(endedAt: start.addingTimeInterval(14 * 3600)))
    }
}
#endif
