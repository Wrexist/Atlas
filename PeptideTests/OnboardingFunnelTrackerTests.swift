import XCTest
@testable import Peptide

/// Covers OnboardingFunnelTracker's snapshot persistence, idempotency,
/// and event recording. The tracker is local-only and backed by
/// UserDefaults; tests scrub the keys in setUp / tearDown so a parallel
/// test run doesn't contaminate state.
@MainActor
final class OnboardingFunnelTrackerTests: XCTestCase {

    private let snapshotKey  = "onboarding.funnel.snapshot.v1"
    private let sessionIDKey = "onboarding.funnel.sessionID.v1"
    private let completedKey = "onboarding.funnel.completed.v1"

    override func setUp() {
        super.setUp()
        clearKeys()
    }

    override func tearDown() {
        clearKeys()
        super.tearDown()
    }

    private func clearKeys() {
        UserDefaults.standard.removeObject(forKey: snapshotKey)
        UserDefaults.standard.removeObject(forKey: sessionIDKey)
        UserDefaults.standard.removeObject(forKey: completedKey)
    }

    // MARK: - Step recording

    func test_recordStepEntered_persistsToSnapshot() {
        OnboardingFunnelTracker.recordStepEntered("welcome", index: 0)
        let snapshot = OnboardingFunnelTracker.snapshot
        XCTAssertNotNil(snapshot.steps["welcome"])
        XCTAssertEqual(snapshot.steps["welcome"]?.index, 0)
    }

    func test_recordStepEntered_isIdempotentForSameStep() {
        OnboardingFunnelTracker.recordStepEntered("welcome", index: 0)
        let firstTimestamp = OnboardingFunnelTracker.snapshot.steps["welcome"]?.timestamp

        // Sleep just long enough that a real second timestamp would differ.
        Thread.sleep(forTimeInterval: 0.05)
        OnboardingFunnelTracker.recordStepEntered("welcome", index: 0)

        let secondTimestamp = OnboardingFunnelTracker.snapshot.steps["welcome"]?.timestamp
        XCTAssertEqual(firstTimestamp, secondTimestamp,
                       "Re-entries from back-navigation must not overwrite the first-entry timestamp.")
    }

    func test_multipleStepsRecorded_allPresentInSnapshot() {
        OnboardingFunnelTracker.recordStepEntered("welcome", index: 0)
        OnboardingFunnelTracker.recordStepEntered("name", index: 4)
        OnboardingFunnelTracker.recordStepEntered("goal", index: 5)

        let snapshot = OnboardingFunnelTracker.snapshot
        XCTAssertEqual(snapshot.steps.count, 3)
        XCTAssertEqual(snapshot.steps["welcome"]?.index, 0)
        XCTAssertEqual(snapshot.steps["name"]?.index, 4)
        XCTAssertEqual(snapshot.steps["goal"]?.index, 5)
    }

    // MARK: - Events

    func test_recordEvent_appendsToSnapshot() {
        OnboardingFunnelTracker.recordEvent("paywall_accepted")
        let snapshot = OnboardingFunnelTracker.snapshot
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.events.first?.name, "paywall_accepted")
    }

    func test_recordEvent_preservesChronologicalOrder() {
        OnboardingFunnelTracker.recordEvent("first")
        Thread.sleep(forTimeInterval: 0.01)
        OnboardingFunnelTracker.recordEvent("second")
        Thread.sleep(forTimeInterval: 0.01)
        OnboardingFunnelTracker.recordEvent("third")

        let names = OnboardingFunnelTracker.snapshot.events.map(\.name)
        XCTAssertEqual(names, ["first", "second", "third"])
    }

    func test_recordEvent_allowsDuplicates() {
        // Unlike step entries, events ARE duplicate-allowed — a user can
        // tap "creator_code_invalid" three times before succeeding, and
        // each attempt is a real signal.
        OnboardingFunnelTracker.recordEvent("creator_code_invalid")
        OnboardingFunnelTracker.recordEvent("creator_code_invalid")
        OnboardingFunnelTracker.recordEvent("creator_code_invalid")

        XCTAssertEqual(OnboardingFunnelTracker.snapshot.events.count, 3)
    }

    // MARK: - Completion

    func test_recordCompletion_setsCompletedFlag() {
        XCTAssertFalse(OnboardingFunnelTracker.hasCompleted)
        OnboardingFunnelTracker.recordCompletion()
        XCTAssertTrue(OnboardingFunnelTracker.hasCompleted)
    }

    func test_recordCompletion_stampsCompletedAt() {
        OnboardingFunnelTracker.recordCompletion()
        XCTAssertNotNil(OnboardingFunnelTracker.snapshot.completedAt)
    }

    // MARK: - Session ID

    func test_sessionID_isStableAcrossEvents() {
        OnboardingFunnelTracker.recordEvent("first")
        let firstSessionID = OnboardingFunnelTracker.snapshot.sessionID

        OnboardingFunnelTracker.recordEvent("second")
        let secondSessionID = OnboardingFunnelTracker.snapshot.sessionID

        XCTAssertEqual(firstSessionID, secondSessionID,
                       "Session ID must persist across events within a session.")
        XCTAssertFalse(firstSessionID.isEmpty)
    }

    // MARK: - Round-trip persistence

    func test_snapshot_roundTripsThroughUserDefaults() {
        OnboardingFunnelTracker.recordStepEntered("welcome", index: 0)
        OnboardingFunnelTracker.recordEvent("paywall_accepted")
        OnboardingFunnelTracker.recordCompletion()

        // Re-fetch — the snapshot should decode cleanly from
        // UserDefaults rather than rebuilding from in-memory state.
        let snapshot = OnboardingFunnelTracker.snapshot
        XCTAssertEqual(snapshot.steps.count, 1)
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertNotNil(snapshot.completedAt)
    }
}
