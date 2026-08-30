import XCTest
@testable import Peptide

/// The three streak call sites (home ring, insight line, weekly recap)
/// all route through `StreakEngine`, so these cases are the contract for
/// every number the user sees.
final class StreakEngineTests: XCTestCase {

    // MARK: - Fixtures

    private let calendar = Calendar.current
    private let protocolID = UUID()

    /// A fixed reference day keeps the walk deterministic — a test run
    /// straddling midnight would otherwise flip results.
    private var today: Date {
        calendar.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
    }

    private func day(_ daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
    }

    private func entry(daysAgo: Int, completed: Bool = true) -> ProtocolEntry {
        ProtocolEntry(
            id: UUID(),
            protocolId: protocolID,
            peptide: MockPeptides.bpc157,
            date: day(daysAgo),
            dose: "250mcg",
            notes: "",
            completed: completed
        )
    }

    private func activeProtocol(status: ProtocolStatus = .active) -> PeptideProtocol {
        PeptideProtocol(
            id: protocolID,
            name: "Test",
            peptides: [MockPeptides.bpc157],
            schedule: ProtocolSchedule(daysOfWeek: [1, 2, 3, 4, 5, 6, 7], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: 8,
            startDate: day(60),
            status: status,
            notes: ""
        )
    }

    private func streak(
        _ entries: [ProtocolEntry],
        frozen: Set<String> = [],
        protocols: [PeptideProtocol]? = nil
    ) -> Int {
        StreakEngine.currentStreak(
            entriesByDay: StreakEngine.activeEntriesByDay(
                entries: entries,
                protocols: protocols ?? [activeProtocol()],
                calendar: calendar
            ),
            frozenDayKeys: frozen,
            today: today,
            calendar: calendar
        )
    }

    // MARK: - No gap

    func test_currentStreak_consecutiveCompletedDays_countsEveryDay() {
        let entries = (0..<5).map { entry(daysAgo: $0) }
        XCTAssertEqual(streak(entries), 5)
    }

    func test_currentStreak_noEntries_isZero() {
        XCTAssertEqual(streak([]), 0)
    }

    // MARK: - Gaps

    func test_currentStreak_oneDayGap_survives() {
        // Logged today, day 1 missing entirely (a bye), logged days 2–3.
        let entries = [entry(daysAgo: 0), entry(daysAgo: 2), entry(daysAgo: 3)]
        XCTAssertEqual(streak(entries), 3)
    }

    func test_currentStreak_twoDayGap_survives() {
        let entries = [entry(daysAgo: 0), entry(daysAgo: 3), entry(daysAgo: 4)]
        XCTAssertEqual(streak(entries), 3)
    }

    func test_currentStreak_threeDayGap_endsTheStreak() {
        // Three empty days in a row exceeds the tolerance, so the days
        // before the gap don't count.
        let entries = [entry(daysAgo: 0), entry(daysAgo: 4), entry(daysAgo: 5)]
        XCTAssertEqual(streak(entries), 1)
    }

    func test_currentStreak_scheduledButNotCompleted_breaksImmediately() {
        // A day with entries and none completed is a real miss, not a
        // bye — it breaks the streak even though only one day is bad.
        let entries = [entry(daysAgo: 0), entry(daysAgo: 1, completed: false), entry(daysAgo: 2)]
        XCTAssertEqual(streak(entries), 1)
    }

    // MARK: - Freezes

    func test_currentStreak_freezeShieldsAMissedDay() {
        let entries = [entry(daysAgo: 0), entry(daysAgo: 1, completed: false), entry(daysAgo: 2)]
        let frozen: Set<String> = [StreakFreezeService.dayKey(for: day(1))]
        // Today + the frozen day + the day before it.
        XCTAssertEqual(streak(entries, frozen: frozen), 3)
    }

    func test_currentStreak_freezeShieldsAnEmptyDayWithoutSpendingTolerance() {
        // Days 1–3 are empty. Freezing day 2 splits the run so neither
        // side exceeds the two-bye tolerance.
        let entries = [entry(daysAgo: 0), entry(daysAgo: 4)]
        let frozen: Set<String> = [StreakFreezeService.dayKey(for: day(2))]
        XCTAssertEqual(streak(entries, frozen: frozen), 3)
    }

    func test_currentStreak_unrelatedFreezeDay_changesNothing() {
        let entries = (0..<3).map { entry(daysAgo: $0) }
        let frozen: Set<String> = [StreakFreezeService.dayKey(for: day(40))]
        XCTAssertEqual(streak(entries, frozen: frozen), 3)
    }

    // MARK: - Today grace

    func test_currentStreak_todayNotYetLogged_keepsYesterdaysStreak() {
        // Nothing logged today at all — the walk starts at yesterday
        // instead of breaking.
        let entries = (1..<4).map { entry(daysAgo: $0) }
        XCTAssertEqual(streak(entries), 3)
    }

    func test_currentStreak_todayLoggedButNotCompleted_stillGetsGrace() {
        // An entry exists for today but isn't ticked yet. The day is
        // skipped rather than counted as a miss.
        let entries = [entry(daysAgo: 0, completed: false)] + (1..<4).map { entry(daysAgo: $0) }
        XCTAssertEqual(streak(entries), 3)
    }

    // MARK: - Active protocols only

    func test_currentStreak_pausedProtocolEntries_areIgnored() {
        let entries = (0..<5).map { entry(daysAgo: $0) }
        XCTAssertEqual(streak(entries, protocols: [activeProtocol(status: .paused)]), 0)
    }

    // MARK: - Best streak

    func test_bestStreak_findsLongestHistoricalRun() {
        // A 4-day run, a hard break (scheduled and missed), then a
        // 2-day run ending today.
        var entries = (10..<14).map { entry(daysAgo: $0) }
        entries.append(entry(daysAgo: 9, completed: false))
        entries.append(contentsOf: (0..<2).map { entry(daysAgo: $0) })

        let best = StreakEngine.bestStreak(
            entriesByDay: StreakEngine.activeEntriesByDay(
                entries: entries,
                protocols: [activeProtocol()],
                calendar: calendar
            ),
            frozenDayKeys: [],
            today: today,
            calendar: calendar
        )
        XCTAssertEqual(best, 4)
    }

    func test_bestStreak_noEntries_isZero() {
        let best = StreakEngine.bestStreak(
            entriesByDay: [:],
            frozenDayKeys: [],
            today: today,
            calendar: calendar
        )
        XCTAssertEqual(best, 0)
    }

    // MARK: - Agreement between call sites

    func test_currentStreak_matchesTheInsightEngineNumber() {
        // The regression this engine exists to prevent: the insight
        // line quoting a different streak than the ring because it
        // ignored freezes.
        let entries = (0..<8).map { $0 == 3 ? entry(daysAgo: $0, completed: false) : entry(daysAgo: $0) }
        let frozen: Set<String> = [StreakFreezeService.dayKey(for: day(3))]

        let engineStreak = streak(entries, frozen: frozen)
        XCTAssertEqual(engineStreak, 8)

        let insights = InsightEngine.generateInsights(
            from: entries,
            protocols: [activeProtocol()],
            frozenDayKeys: frozen
        )
        XCTAssertTrue(
            insights.contains { $0.description.contains("\(engineStreak) days in a row") },
            "Insight copy should quote the engine's streak, got: \(insights.map(\.description))"
        )
    }
}
