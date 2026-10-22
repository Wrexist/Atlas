import XCTest
@testable import Peptide

/// Cache-freshness behaviour of `WeeklySummaryService`. The generation
/// pipeline itself (gates, proxy call, offline fallback) needs a network
/// double; these tests pin the invalidation contract: a cached summary
/// must never outlive the week's source data.
@MainActor
final class WeeklySummaryServiceTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.firstWeekday = 2
        return c
    }

    /// Pinned Monday (Jan 5 2026) — same anchor as WeeklySummaryEngineTests.
    private var weekMonday: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 5
        components.hour = 9
        return calendar.date(from: components)!
    }

    private func entry(daysFromMonday: Int, completed: Bool) -> ProtocolEntry {
        ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: MockPeptides.bpc157,
            date: calendar.date(byAdding: .day, value: daysFromMonday, to: weekMonday)!,
            dose: "250mcg",
            notes: "",
            completed: completed
        )
    }

    /// Builds the aggregate for the fixture week and a summary stamped
    /// with its fingerprint — what `generate(...)` would have cached.
    private func makeCachedSummary(
        entries: [ProtocolEntry],
        profile: inout UserProfile,
        kind: WeeklySummary.Kind = .ai
    ) throws -> WeeklySummary {
        let aggregate = try XCTUnwrap(WeeklySummaryEngine.build(
            profile: profile,
            protocols: [],
            entries: entries,
            referenceDate: weekMonday
        ))
        let summary = WeeklySummary(
            weekStart: aggregate.weekStart,
            text: "Cached recap",
            keyStats: WeeklySummary.KeyStats(
                compliancePct: aggregate.compliance.pct,
                dosesCompleted: aggregate.compliance.completed,
                dosesTotal: aggregate.compliance.total,
                currentStreak: aggregate.streak.current,
                avgCheckInScore: nil,
                avgCalories: nil,
                hrvDelta: nil
            ),
            kind: kind,
            generatedAt: weekMonday,
            sourceFingerprint: WeeklySummaryService.sourceFingerprint(of: aggregate)
        )
        WeeklySummaryService.shared.record(summary, in: &profile)
        return summary
    }

    func test_weeklySummaryCache_invalidatedOnSourceEdit() throws {
        var profile = UserProfile.fresh
        var entries = [
            entry(daysFromMonday: 0, completed: true),
            entry(daysFromMonday: 1, completed: true),
            entry(daysFromMonday: 2, completed: true),
            entry(daysFromMonday: 3, completed: false),
        ]
        let summary = try makeCachedSummary(entries: entries, profile: &profile)

        // Untouched source data → the cache is served.
        XCTAssertEqual(
            WeeklySummaryService.shared.cachedIfFresh(
                profile: profile, protocols: [], entries: entries,
                referenceDate: weekMonday
            )?.weekStart,
            summary.weekStart
        )

        // Edit source data inside the cached week (log the missed dose).
        entries[3].completed = true

        // The stale cache must not be served any more.
        XCTAssertNil(
            WeeklySummaryService.shared.cachedIfFresh(
                profile: profile, protocols: [], entries: entries,
                referenceDate: weekMonday
            ),
            "A summary generated before a source edit within its week must be treated as a cache miss"
        )
    }

    func test_weeklySummaryCache_legacyEntryWithoutFingerprint_isTreatedAsStale() throws {
        var profile = UserProfile.fresh
        let entries = [
            entry(daysFromMonday: 0, completed: true),
            entry(daysFromMonday: 1, completed: true),
            entry(daysFromMonday: 2, completed: true),
        ]
        var summary = try makeCachedSummary(entries: entries, profile: &profile)
        summary.sourceFingerprint = nil
        profile.weeklySummaries[summary.weekStart] = summary

        XCTAssertNil(
            WeeklySummaryService.shared.cachedIfFresh(
                profile: profile, protocols: [], entries: entries,
                referenceDate: weekMonday
            ),
            "Pre-fingerprint cache entries must regenerate once rather than risk staleness"
        )
    }

    func test_weeklySummaryCache_fingerprint_isDeterministic() throws {
        let entries = [
            entry(daysFromMonday: 0, completed: true),
            entry(daysFromMonday: 1, completed: true),
            entry(daysFromMonday: 2, completed: true),
        ]
        let a = try XCTUnwrap(WeeklySummaryEngine.build(
            profile: .fresh, protocols: [], entries: entries, referenceDate: weekMonday
        ))
        let b = try XCTUnwrap(WeeklySummaryEngine.build(
            profile: .fresh, protocols: [], entries: entries, referenceDate: weekMonday
        ))
        XCTAssertEqual(
            WeeklySummaryService.sourceFingerprint(of: a),
            WeeklySummaryService.sourceFingerprint(of: b)
        )
        XCTAssertFalse(WeeklySummaryService.sourceFingerprint(of: a).isEmpty)
    }

    func test_staleSummary_generatedRecently_isNotDueForRegeneration() throws {
        var profile = UserProfile.fresh
        let entries = [
            entry(daysFromMonday: 0, completed: true),
            entry(daysFromMonday: 1, completed: true),
            entry(daysFromMonday: 2, completed: true),
        ]
        let summary = try makeCachedSummary(entries: entries, profile: &profile)

        XCTAssertFalse(WeeklySummaryService.isDueForRegeneration(
            summary,
            now: summary.generatedAt.addingTimeInterval(60 * 60)
        ))
    }

    func test_staleSummary_olderThanInterval_isDueForRegeneration() throws {
        var profile = UserProfile.fresh
        let entries = [
            entry(daysFromMonday: 0, completed: true),
            entry(daysFromMonday: 1, completed: true),
            entry(daysFromMonday: 2, completed: true),
        ]
        let summary = try makeCachedSummary(entries: entries, profile: &profile)

        XCTAssertTrue(WeeklySummaryService.isDueForRegeneration(
            summary,
            now: summary.generatedAt.addingTimeInterval(WeeklySummaryService.staleRegenerationInterval)
        ))
    }

    func test_staleOfflineFallback_isDueForRegenerationAfterRetryInterval() throws {
        var profile = UserProfile.fresh
        let entries = [
            entry(daysFromMonday: 0, completed: true),
            entry(daysFromMonday: 1, completed: true),
            entry(daysFromMonday: 2, completed: true),
        ]
        let summary = try makeCachedSummary(entries: entries, profile: &profile, kind: .offline)

        XCTAssertTrue(WeeklySummaryService.isDueForRegeneration(
            summary,
            now: summary.generatedAt.addingTimeInterval(WeeklySummaryService.offlineRetryInterval)
        ))
    }

    func test_offlineFallback_olderThanRetryInterval_isTreatedAsStale() throws {
        var profile = UserProfile.fresh
        let entries = [
            entry(daysFromMonday: 0, completed: true),
            entry(daysFromMonday: 1, completed: true),
            entry(daysFromMonday: 2, completed: true),
        ]
        let summary = try makeCachedSummary(entries: entries, profile: &profile, kind: .offline)
        let aggregate = try XCTUnwrap(WeeklySummaryEngine.build(
            profile: profile, protocols: [], entries: entries, referenceDate: weekMonday
        ))
        let interval = WeeklySummaryService.offlineRetryInterval

        XCTAssertTrue(WeeklySummaryService.isFresh(
            summary, for: aggregate, now: weekMonday.addingTimeInterval(interval - 60)
        ))
        XCTAssertFalse(
            WeeklySummaryService.isFresh(summary, for: aggregate, now: weekMonday.addingTimeInterval(interval + 60)),
            "An offline fallback must retry the proxy instead of pinning the template text"
        )
    }
}
