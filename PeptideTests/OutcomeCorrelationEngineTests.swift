import XCTest
@testable import Peptide

/// Pins the dose-day vs off-day correlation math (audit Phase 9 —
/// untested engines). Dates derive from a start-of-day "today"
/// anchor because `trendPoints` windows against the real clock;
/// the bucket math itself is fully input-driven.
@MainActor
final class OutcomeCorrelationEngineTests: XCTestCase {

    private let calendar = Calendar.current
    private lazy var today = calendar.startOfDay(for: Date())

    private func day(_ daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: today)!
    }

    private func makeEntry(daysAgo: Int, completed: Bool = true) -> ProtocolEntry {
        ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: MockPeptides.bpc157,
            date: day(daysAgo),
            dose: "250mcg",
            notes: "",
            completed: completed
        )
    }

    private func makeOutcome(
        daysAgo: Int,
        energy: Int = 3,
        sleep: Int = 3,
        recovery: Int = 3,
        mood: Int = 3,
        focus: Int = 3
    ) -> OutcomeEntry {
        OutcomeEntry(
            date: day(daysAgo),
            energy: energy,
            sleepQuality: sleep,
            recovery: recovery,
            mood: mood,
            focus: focus
        )
    }

    private func correlation(
        _ dimension: OutcomeDimension,
        outcomes: [OutcomeEntry],
        entries: [ProtocolEntry]
    ) -> OutcomeCorrelationEngine.DimensionCorrelation {
        OutcomeCorrelationEngine
            .dimensionCorrelations(outcomes: outcomes, entries: entries)
            .first { $0.dimension == dimension }!
    }

    // MARK: - Bucket split

    func test_dimensionCorrelations_splitsByCompletedDoseDays() {
        let entries = (0...3).map { makeEntry(daysAgo: $0) }
        let outcomes = (0...3).map { makeOutcome(daysAgo: $0, energy: 4) }
            + (4...7).map { makeOutcome(daysAgo: $0, energy: 3) }

        let energy = correlation(.energy, outcomes: outcomes, entries: entries)
        XCTAssertEqual(energy.onDoseDays, 4.0)
        XCTAssertEqual(energy.offDoseDays, 3.0)
        XCTAssertEqual(energy.delta, 1.0)
        XCTAssertEqual(energy.doseDayCount, 4)
        XCTAssertEqual(energy.offDayCount, 4)
        XCTAssertTrue(energy.hasEnoughData)
    }

    func test_dimensionCorrelations_ignoresIncompleteEntries() {
        // A scheduled-but-skipped dose must not turn its day into a
        // "dosing day".
        let entries = [makeEntry(daysAgo: 0, completed: false)]
        let outcomes = [makeOutcome(daysAgo: 0, energy: 5)]

        let energy = correlation(.energy, outcomes: outcomes, entries: entries)
        XCTAssertNil(energy.onDoseDays)
        XCTAssertEqual(energy.offDoseDays, 5.0)
        XCTAssertEqual(energy.doseDayCount, 0)
        XCTAssertEqual(energy.offDayCount, 1)
    }

    func test_dimensionCorrelations_emptyOutcomes_yieldNilAverages() {
        let energy = correlation(.energy, outcomes: [], entries: [makeEntry(daysAgo: 0)])
        XCTAssertNil(energy.onDoseDays)
        XCTAssertNil(energy.offDoseDays)
        XCTAssertNil(energy.delta)
        XCTAssertFalse(energy.hasEnoughData)
    }

    // MARK: - Headline selection

    func test_headline_picksStrongestPositiveDelta() {
        let entries = (0...3).map { makeEntry(daysAgo: $0) }
        // Energy moves +2.0 on dose days; mood +0.5; others flat.
        let outcomes = (0...3).map { makeOutcome(daysAgo: $0, energy: 5, mood: 4) } + [
            makeOutcome(daysAgo: 4, energy: 3, mood: 3),
            makeOutcome(daysAgo: 5, energy: 3, mood: 3),
            makeOutcome(daysAgo: 6, energy: 3, mood: 4),
            makeOutcome(daysAgo: 7, energy: 3, mood: 4),
        ]

        let headline = OutcomeCorrelationEngine.headline(outcomes: outcomes, entries: entries)
        XCTAssertEqual(headline?.dimension, .energy)
        XCTAssertEqual(headline?.delta ?? 0, 2.0, accuracy: 0.0001)
    }

    func test_headline_nil_whenDeltaBelowNoiseFloor() {
        let entries = (0...3).map { makeEntry(daysAgo: $0) }
        // Energy delta = 3.25 − 3.0 = 0.25 < 0.3 noise floor.
        let outcomes = [makeOutcome(daysAgo: 0, energy: 4)]
            + (1...3).map { makeOutcome(daysAgo: $0, energy: 3) }
            + (4...7).map { makeOutcome(daysAgo: $0, energy: 3) }

        XCTAssertNil(OutcomeCorrelationEngine.headline(outcomes: outcomes, entries: entries))
    }

    func test_headline_nil_whenEitherBucketUnderSampled() {
        // Three dose days < minimumSamplesPerBucket (4) — a huge
        // delta still must not surface.
        let entries = (0...2).map { makeEntry(daysAgo: $0) }
        let outcomes = (0...2).map { makeOutcome(daysAgo: $0, energy: 5) }
            + (3...9).map { makeOutcome(daysAgo: $0, energy: 1) }

        XCTAssertNil(OutcomeCorrelationEngine.headline(outcomes: outcomes, entries: entries))
    }

    func test_headline_nil_forNegativeCorrelations() {
        // Feeling worse on dose days is real signal but not headline
        // material — the surface only celebrates positive deltas.
        let entries = (0...3).map { makeEntry(daysAgo: $0) }
        let outcomes = (0...3).map { makeOutcome(daysAgo: $0, energy: 2) }
            + (4...7).map { makeOutcome(daysAgo: $0, energy: 4) }

        XCTAssertNil(OutcomeCorrelationEngine.headline(outcomes: outcomes, entries: entries))
    }

    // MARK: - Trend points

    func test_trendPoints_windowsSortsAndFlagsDoseDays() {
        let outcomes = (0...9).map { makeOutcome(daysAgo: $0, energy: 4) }
        let entries = [makeEntry(daysAgo: 2)]

        let points = OutcomeCorrelationEngine.trendPoints(outcomes: outcomes, entries: entries, days: 7)

        XCTAssertEqual(points.count, 7)
        XCTAssertEqual(points.first?.date, day(6))
        XCTAssertEqual(points.last?.date, day(0))
        XCTAssertEqual(points.map(\.onDoseDay), [false, false, false, false, true, false, false])
        XCTAssertEqual(points.first?.composite ?? 0, (4 + 3 + 3 + 3 + 3) / 5.0, accuracy: 0.0001)
    }

    func test_trendPoints_skipsDaysWithoutCheckIn() {
        let outcomes = [0, 2, 4].map { makeOutcome(daysAgo: $0) }
        let points = OutcomeCorrelationEngine.trendPoints(outcomes: outcomes, entries: [], days: 7)
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points.map(\.date), [day(4), day(2), day(0)])
    }
}
