import XCTest
@testable import Peptide

final class SleepScoreEngineTests: XCTestCase {

    /// 2025-10-10 22:00 UTC. Whole seconds, so nothing depends on
    /// sub-second rounding.
    private let bedtime = Date(timeIntervalSince1970: 1_760_133_600)

    private func segment(
        _ stage: SleepScoreEngine.Stage,
        at hour: Double,
        for hours: Double,
        source: String = "com.apple.health"
    ) -> SleepScoreEngine.Segment {
        let start = bedtime.addingTimeInterval(hour * 3600)
        return .init(stage: stage, start: start, end: start.addingTimeInterval(hours * 3600), source: source)
    }

    // MARK: - Night selection

    func test_night_noSegments_returnsNil() {
        XCTAssertNil(SleepScoreEngine.night(from: []))
    }

    func test_night_onlyAwake_returnsNil() {
        XCTAssertNil(SleepScoreEngine.night(from: [segment(.awake, at: 0, for: 1)]))
    }

    func test_night_stagedNight_sumsEachStage() throws {
        let night = try XCTUnwrap(SleepScoreEngine.night(from: [
            segment(.core, at: 0, for: 2),
            segment(.deep, at: 2, for: 1),
            segment(.awake, at: 3, for: 0.25),
            segment(.rem, at: 3.25, for: 1.5),
        ]))
        XCTAssertEqual(night.core, 2 * 3600)
        XCTAssertEqual(night.deep, 3600)
        XCTAssertEqual(night.rem, 1.5 * 3600)
        XCTAssertEqual(night.awake, 0.25 * 3600)
        XCTAssertEqual(night.start, bedtime)
        XCTAssertEqual(night.end, bedtime.addingTimeInterval(4.75 * 3600))
        XCTAssertTrue(night.hasStages)
    }

    /// Apple Watch and a third-party tracker both log the same night.
    /// Keeping only the source with the most sleep stops a double count.
    func test_night_twoSourcesOverlap_keepsOnlyTheDominantSource() throws {
        let night = try XCTUnwrap(SleepScoreEngine.night(from: [
            segment(.core, at: 0, for: 8, source: "watch"),
            segment(.unspecified, at: 0.5, for: 6, source: "tracker"),
        ]))
        XCTAssertEqual(night.asleep, 8 * 3600)
        XCTAssertEqual(night.unspecified, 0)
    }

    func test_night_napAfterNight_keepsTheNight() throws {
        let night = try XCTUnwrap(SleepScoreEngine.night(from: [
            segment(.core, at: 0, for: 7),
            segment(.core, at: 16, for: 1),
        ]))
        XCTAssertEqual(night.asleep, 7 * 3600)
        XCTAssertEqual(night.start, bedtime)
    }

    /// A nap long enough to pass for a night (3.5 h, mid-afternoon) must
    /// still lose to the night before it.
    func test_night_longNapAfterNight_keepsTheNight() throws {
        let night = try XCTUnwrap(SleepScoreEngine.night(from: [
            segment(.core, at: 0, for: 7),
            segment(.core, at: 16, for: 3.5),
        ]))
        XCTAssertEqual(night.start, bedtime)
        XCTAssertEqual(night.asleep, 7 * 3600)
    }

    func test_night_twoNightsInWindow_keepsTheLatest() throws {
        let night = try XCTUnwrap(SleepScoreEngine.night(from: [
            segment(.core, at: -24, for: 7),
            segment(.core, at: 0, for: 6),
        ]))
        XCTAssertEqual(night.start, bedtime)
        XCTAssertEqual(night.asleep, 6 * 3600)
    }

    // MARK: - Score

    func test_score_fullStagedNightAtTarget_is100() throws {
        let night = try XCTUnwrap(SleepScoreEngine.night(from: [
            segment(.core, at: 0, for: 4.8),
            segment(.deep, at: 4.8, for: 1.6),
            segment(.rem, at: 6.4, for: 1.6),
        ]))
        XCTAssertEqual(SleepScoreEngine.score(night, targetHours: 8), 100)
    }

    /// Restorative share 0.3 of a 0.4 target scores 0.75 of its weight:
    /// 0.60 + 0.25 × 0.75 + 0.15 = 0.9375.
    func test_score_lowRestorativeShare_losesPartOfThatWeight() throws {
        let night = try XCTUnwrap(SleepScoreEngine.night(from: [
            segment(.core, at: 0, for: 5.6),
            segment(.deep, at: 5.6, for: 1.2),
            segment(.rem, at: 6.8, for: 1.2),
        ]))
        XCTAssertEqual(SleepScoreEngine.score(night, targetHours: 8), 94)
    }

    /// Two hours awake in a ten-hour night is a 20% awake share, past the
    /// 15% ceiling, so continuity contributes nothing.
    func test_score_heavilyInterruptedNight_losesContinuity() throws {
        let night = try XCTUnwrap(SleepScoreEngine.night(from: [
            segment(.core, at: 0, for: 4.8),
            segment(.awake, at: 4.8, for: 2),
            segment(.deep, at: 6.8, for: 1.6),
            segment(.rem, at: 8.4, for: 1.6),
        ]))
        XCTAssertEqual(SleepScoreEngine.score(night, targetHours: 8), 85)
    }

    /// A tracker without stages isn't punished for missing deep/REM: the
    /// duration and continuity weights renormalise to the whole score.
    /// (0.60 × 0.75 + 0.15) / 0.75 = 0.8.
    func test_score_unstagedShortNight_scoresOnDurationAndContinuity() throws {
        let night = try XCTUnwrap(SleepScoreEngine.night(from: [
            segment(.unspecified, at: 0, for: 6),
        ]))
        XCTAssertFalse(night.hasStages)
        XCTAssertEqual(SleepScoreEngine.score(night, targetHours: 8), 80)
    }

    /// Seven unspecified hours with ten minutes of REM is an unstaged
    /// night: scoring its 2% restorative share would cost ~24 points the
    /// source never measured.
    func test_score_mostlyUnspecifiedNight_scoresAsUnstaged() throws {
        let night = try XCTUnwrap(SleepScoreEngine.night(from: [
            segment(.unspecified, at: 0, for: 7),
            segment(.rem, at: 7, for: 1.0 / 6),
        ]))
        XCTAssertFalse(night.hasStages)
        // (0.60 × 7.17/8 + 0.15) / 0.75 = 0.917
        XCTAssertEqual(SleepScoreEngine.score(night, targetHours: 8), 92)
    }

    func test_score_sleepBeyondTarget_doesNotExceed100() throws {
        let night = try XCTUnwrap(SleepScoreEngine.night(from: [
            segment(.core, at: 0, for: 6),
            segment(.deep, at: 6, for: 2),
            segment(.rem, at: 8, for: 2),
        ]))
        XCTAssertEqual(SleepScoreEngine.score(night, targetHours: 8), 100)
    }
}
