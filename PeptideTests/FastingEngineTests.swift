import XCTest
@testable import Peptide

final class FastingEngineTests: XCTestCase {

    private let stockholm: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        stockholm.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func fast(start: Date, hours: Double?, target: Double = 16) -> FastSession {
        FastSession(
            startedAt: start,
            endedAt: hours.map { start.addingTimeInterval($0 * 3600) },
            targetHours: target,
            plan: .sixteen
        )
    }

    // MARK: - Stage at time t

    func test_stage_followsElapsedHourThresholds() {
        XCTAssertEqual(FastingEngine.stage(forElapsed: 0), .fed)
        XCTAssertEqual(FastingEngine.stage(forElapsed: 3.99 * 3600), .fed)
        XCTAssertEqual(FastingEngine.stage(forElapsed: 4 * 3600), .earlyFasting)
        XCTAssertEqual(FastingEngine.stage(forElapsed: 11.9 * 3600), .earlyFasting)
        XCTAssertEqual(FastingEngine.stage(forElapsed: 12 * 3600), .fatBurning)
        XCTAssertEqual(FastingEngine.stage(forElapsed: 16 * 3600), .ketosis)
        XCTAssertEqual(FastingEngine.stage(forElapsed: 40 * 3600), .ketosis)
    }

    func test_stage_ofActiveFast_usesNow() {
        let start = date(2026, 10, 20, 20)
        let open = fast(start: start, hours: nil)
        XCTAssertEqual(FastingEngine.stage(of: open, at: start.addingTimeInterval(13 * 3600)), .fatBurning)
        XCTAssertEqual(FastingEngine.timeUntilNextStage(of: open, at: start.addingTimeInterval(13 * 3600)), 3 * 3600)
    }

    func test_stage_ofEndedFast_freezesAtEnd() {
        let start = date(2026, 10, 20, 20)
        let ended = fast(start: start, hours: 10)
        XCTAssertEqual(FastingEngine.stage(of: ended, at: start.addingTimeInterval(48 * 3600)), .earlyFasting)
    }

    func test_timeUntilNextStage_inLastStage_isNil() {
        let start = date(2026, 10, 20, 20)
        XCTAssertNil(FastingEngine.timeUntilNextStage(of: fast(start: start, hours: nil), at: start.addingTimeInterval(20 * 3600)))
    }

    // MARK: - Progress

    func test_progressAndRemaining_halfwayThroughSixteenHours() {
        let start = date(2026, 10, 20, 20)
        let open = fast(start: start, hours: nil)
        let now = start.addingTimeInterval(8 * 3600)
        XCTAssertEqual(FastingEngine.progress(open, at: now), 0.5, accuracy: 0.0001)
        XCTAssertEqual(FastingEngine.remaining(open, at: now), 8 * 3600, accuracy: 0.001)
    }

    func test_progress_pastTarget_clampsToOne() {
        let start = date(2026, 10, 20, 20)
        let open = fast(start: start, hours: nil)
        XCTAssertEqual(FastingEngine.progress(open, at: start.addingTimeInterval(20 * 3600)), 1)
        XCTAssertEqual(FastingEngine.remaining(open, at: start.addingTimeInterval(20 * 3600)), 0)
    }

    func test_elapsed_clockBeforeStart_isZero() {
        let start = date(2026, 10, 20, 20)
        XCTAssertEqual(FastingEngine.elapsed(fast(start: start, hours: nil), at: start.addingTimeInterval(-60)), 0)
    }

    func test_metGoal_requiresEndedFastReachingTarget() {
        let start = date(2026, 10, 20, 20)
        XCTAssertTrue(FastingEngine.metGoal(fast(start: start, hours: 16)))
        XCTAssertFalse(FastingEngine.metGoal(fast(start: start, hours: 15.9)))
        XCTAssertFalse(FastingEngine.metGoal(fast(start: start, hours: nil)))
    }

    // MARK: - Crossing midnight

    func test_fastCrossingMidnight_countsForTheDayItEnds() {
        let overnight = fast(start: date(2026, 10, 19, 20), hours: 16) // ends 20 Oct 12:00
        let days = FastingEngine.completionDays([overnight], calendar: stockholm)
        XCTAssertEqual(days, [stockholm.startOfDay(for: date(2026, 10, 20, 12))])
        XCTAssertEqual(FastingEngine.currentStreak([overnight], asOf: date(2026, 10, 20, 18), calendar: stockholm), 1)
    }

    // MARK: - Streaks

    func test_currentStreak_consecutiveDaysEndingToday() {
        let fasts = (18...20).map { fast(start: date(2026, 10, $0, 0), hours: 16) }
        XCTAssertEqual(FastingEngine.currentStreak(fasts, asOf: date(2026, 10, 20, 22), calendar: stockholm), 3)
    }

    func test_currentStreak_todayNotYetDone_keepsYesterdaysRun() {
        let fasts = (18...19).map { fast(start: date(2026, 10, $0, 0), hours: 16) }
        XCTAssertEqual(FastingEngine.currentStreak(fasts, asOf: date(2026, 10, 20, 9), calendar: stockholm), 2)
    }

    func test_currentStreak_missedDay_resetsToZero() {
        let fasts = [fast(start: date(2026, 10, 17, 0), hours: 16)]
        XCTAssertEqual(FastingEngine.currentStreak(fasts, asOf: date(2026, 10, 20, 9), calendar: stockholm), 0)
    }

    func test_currentStreak_fastEndedEarly_doesNotCount() {
        let fasts = [
            fast(start: date(2026, 10, 19, 0), hours: 16),
            fast(start: date(2026, 10, 20, 0), hours: 10),
        ]
        XCTAssertEqual(FastingEngine.currentStreak(fasts, asOf: date(2026, 10, 20, 22), calendar: stockholm), 1)
    }

    func test_bestStreak_findsLongestRunAcrossGaps() {
        let fasts = [1, 2, 3, 5, 6].map { fast(start: date(2026, 10, $0, 0), hours: 16) }
        XCTAssertEqual(FastingEngine.bestStreak(fasts, calendar: stockholm), 3)
        XCTAssertEqual(FastingEngine.bestStreak([], calendar: stockholm), 0)
    }

    func test_twoFastsSameDay_countOnce() {
        let fasts = [
            fast(start: date(2026, 10, 20, 0), hours: 16),
            fast(start: date(2026, 10, 19, 22), hours: 16),
        ]
        XCTAssertEqual(FastingEngine.bestStreak(fasts, calendar: stockholm), 1)
    }

    // MARK: - DST

    func test_fastAcrossSpringForward_lastsFullTargetInElapsedTime() {
        // Stockholm springs forward at 02:00 on 29 March 2026.
        let start = date(2026, 3, 28, 22)
        let open = fast(start: start, hours: nil)
        let targetEnd = open.targetEnd
        XCTAssertEqual(targetEnd.timeIntervalSince(start), 16 * 3600)
        // Wall clock reads an hour later than a naive 22:00 + 16 h = 14:00.
        XCTAssertEqual(stockholm.component(.hour, from: targetEnd), 15)
        XCTAssertEqual(FastingEngine.stage(of: open, at: targetEnd), .ketosis)
        XCTAssertEqual(FastingEngine.remaining(open, at: targetEnd), 0)
    }

    func test_streak_spanningDSTChange_staysContinuous() {
        let springFasts = (28...30).map { fast(start: date(2026, 3, $0, 0), hours: 16) }
        XCTAssertEqual(FastingEngine.currentStreak(springFasts, asOf: date(2026, 3, 30, 20), calendar: stockholm), 3)
        XCTAssertEqual(FastingEngine.bestStreak(springFasts, calendar: stockholm), 3)

        // Stockholm falls back at 03:00 on 25 October 2026.
        let autumnFasts = (24...26).map { fast(start: date(2026, 10, $0, 0), hours: 16) }
        XCTAssertEqual(FastingEngine.currentStreak(autumnFasts, asOf: date(2026, 10, 26, 20), calendar: stockholm), 3)
        XCTAssertEqual(FastingEngine.bestStreak(autumnFasts, calendar: stockholm), 3)
    }

    // MARK: - Helpers

    func test_averageDuration_ignoresActiveFast() {
        let start = date(2026, 10, 1, 0)
        let fasts = [
            fast(start: start, hours: 14),
            fast(start: start.addingTimeInterval(86_400), hours: 18),
            fast(start: start.addingTimeInterval(2 * 86_400), hours: nil),
        ]
        XCTAssertEqual(FastingEngine.averageDuration(fasts) ?? 0, 16 * 3600, accuracy: 0.001)
        XCTAssertNil(FastingEngine.averageDuration([]))
    }

    func test_clock_formatsHoursAndMinutesWithoutWrapping() {
        XCTAssertEqual(FastingEngine.clock(16 * 3600 + 5 * 60), "16:05")
        XCTAssertEqual(FastingEngine.clock(36 * 3600), "36:00")
        XCTAssertEqual(FastingEngine.clock(-5), "0:00")
    }

    func test_clampedTargetHours_staysInRange() {
        XCTAssertEqual(FastingEngine.clampedTargetHours(0), 1)
        XCTAssertEqual(FastingEngine.clampedTargetHours(100), 72)
        XCTAssertEqual(FastingEngine.clampedTargetHours(.nan), 16)
    }

    func test_fastingProtocol_unknownStoredValue_readsAsCustom() {
        XCTAssertEqual(FastingProtocol(storedRaw: "5:2"), .custom)
        XCTAssertEqual(FastingProtocol(storedRaw: "16:8"), .sixteen)
        XCTAssertEqual(FastingProtocol.omad.defaultFastingHours, 23)
    }
}

/// Store-level round trip against the in-memory SwiftData container.
@MainActor
final class FastingStoreTests: XCTestCase {

    private var store: FastingStore!
    private var repo: SwiftDataRepository!

    override func setUp() {
        super.setUp()
        repo = SwiftDataRepository.shared
        repo.configureForTesting()
        store = FastingStore.shared
        store.load()
    }

    override func tearDown() {
        repo.deleteAll()
        store.load()
        super.tearDown()
    }

    func test_startThenEnd_persistsOneEndedFast() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        store.start(plan: .eighteen, targetHours: 18, remindsAtEnd: false, at: start)
        XCTAssertNotNil(store.active)

        store.end(at: start.addingTimeInterval(18 * 3600))
        store.load()

        XCTAssertNil(store.active)
        XCTAssertEqual(store.ended.count, 1)
        XCTAssertEqual(store.ended.first?.plan, .eighteen)
        XCTAssertTrue(store.ended.first.map(FastingEngine.metGoal) ?? false)
    }

    func test_start_whileFasting_keepsTheOpenFast() {
        let first = store.start(plan: .sixteen, targetHours: 16, remindsAtEnd: false)
        let second = store.start(plan: .twenty, targetHours: 20, remindsAtEnd: false)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(repo.loadFasts().count, 1)
    }

    func test_updateStart_neverMovesIntoTheFuture() {
        let now = Date()
        store.start(plan: .sixteen, targetHours: 16, remindsAtEnd: false, at: now.addingTimeInterval(-3600))
        store.updateStart(now.addingTimeInterval(3600), now: now)
        XCTAssertEqual(store.active?.startedAt, now)
    }

    func test_delete_removesFromHistory() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        store.start(plan: .sixteen, targetHours: 16, remindsAtEnd: false, at: start)
        store.end(at: start.addingTimeInterval(3600))
        guard let id = store.ended.first?.id else { return XCTFail("Expected an ended fast") }
        store.delete(id: id)
        XCTAssertTrue(repo.loadFasts().isEmpty)
    }

    func test_lastPlan_defaultsToSixteenEight() {
        XCTAssertEqual(store.lastPlan.plan, .sixteen)
        XCTAssertEqual(store.lastPlan.hours, 16)
    }
}
