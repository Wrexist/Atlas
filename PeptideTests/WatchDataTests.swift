import XCTest
@testable import Peptide

final class WatchDataTests: XCTestCase {

    /// Whole seconds: the pipeline's `.iso8601` strategy drops fractions.
    private let now = Date(timeIntervalSince1970: 1_760_166_000)

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private var vitals: WatchVitalsSnapshot {
        WatchVitalsSnapshot(
            recoveryScore: 82,
            restingHeartRate: 56,
            restingHeartRateBaseline: 58,
            hrv: 64,
            hrvBaseline: 59,
            sleep: WatchSleepSnapshot(
                score: 84,
                start: now.addingTimeInterval(-8 * 3600),
                end: now,
                deepMinutes: 72,
                coreMinutes: 236,
                remMinutes: 104,
                unspecifiedMinutes: 0,
                awakeMinutes: 18
            ),
            measuredAt: now
        )
    }

    private func entry(completed: Bool) -> WatchEntry {
        WatchEntry(id: UUID(), protocolId: UUID(), peptideName: "BPC-157", abbreviation: "BPC",
                   dose: "250 mcg", scheduledTime: now, completed: completed)
    }

    // MARK: - Wire format

    func test_roundTrip_withVitals_preservesVitals() throws {
        let data = WatchData(todayEntries: [], completedToday: 0, totalToday: 0,
                             lastUpdated: now, vitals: vitals)
        let decoded = try decoder.decode(WatchData.self, from: encoder.encode(data))
        XCTAssertEqual(decoded.vitals, vitals)
    }

    /// A phone on an older build never writes `vitals`. The Watch must
    /// still decode the rest rather than drop the whole push.
    func test_decode_payloadWithoutVitals_decodesWithNilVitals() throws {
        let json = #"{"todayEntries":[],"completedToday":0,"totalToday":0,"lastUpdated":"2025-10-11T07:00:00Z","atlasScore":142}"#
        let decoded = try decoder.decode(WatchData.self, from: Data(json.utf8))
        XCTAssertNil(decoded.vitals)
        XCTAssertEqual(decoded.atlasScore, 142)
    }

    // MARK: - Optimistic dose toggle

    func test_replacingEntries_recountsAndKeepsEveryOtherField() {
        let original = WatchData(
            todayEntries: [entry(completed: false), entry(completed: false)],
            completedToday: 0, totalToday: 2, lastUpdated: now,
            currentStreak: 5, nutrition: nil, atlasScore: 142, atlasTier: "gold",
            healthHabitsDone: 1, healthHabitsTotal: 3, measurementUnit: "metric",
            vitals: vitals
        )
        var toggled = original.todayEntries
        toggled[0].completed = true

        let updated = original.replacingEntries(toggled)

        XCTAssertEqual(updated.completedToday, 1)
        XCTAssertEqual(updated.totalToday, 2)
        XCTAssertEqual(updated.currentStreak, 5)
        XCTAssertEqual(updated.atlasScore, 142)
        XCTAssertEqual(updated.atlasTier, "gold")
        XCTAssertEqual(updated.healthHabitsTotal, 3)
        XCTAssertEqual(updated.measurementUnit, "metric")
        XCTAssertEqual(updated.vitals, vitals)
    }

    // MARK: - Sleep snapshot

    func test_sleepBand_matchesScoreCutPoints() {
        let cases: [(Int, SleepBand)] = [
            (40, .veryLow), (41, .low), (60, .low), (61, .ok),
            (80, .ok), (81, .high), (95, .high), (96, .veryHigh),
        ]
        for (score, band) in cases {
            XCTAssertEqual(SleepBand(score: score), band, "score \(score)")
        }
    }

    func test_sleepSnapshot_asleepMinutes_excludesAwake() {
        XCTAssertEqual(vitals.sleep?.asleepMinutes, 412)
        XCTAssertEqual(vitals.sleep?.hasStages, true)
    }
}
