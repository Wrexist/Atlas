import XCTest
@testable import Peptide

@MainActor
final class BiologyBriefEngineTests: XCTestCase {

    private let inputs = PerformanceAgeEngine.Inputs(
        chronologicalAge: 40, hrvMedian30d: 60, rhrMedian30d: 52,
        sleepHoursMedian30d: 7.8, healthDataDays: 30
    )

    func test_brief_unlocked_carriesEstimateDriversAndMissing() throws {
        let estimate = try XCTUnwrap(PerformanceAgeEngine.estimate(inputs: inputs))
        let resolved = BioAgeStateResolver.Resolved(
            state: .unlocked(estimate: estimate), chronologicalAge: 40, inputs: inputs
        )

        let brief = BiologyBriefEngine.brief(resolved, unit: .metric)

        XCTAssertTrue(brief.contains("Biological Age: \(BioAgeFormat.age(estimate.biologicalAge))"))
        XCTAssertTrue(brief.contains("chronological age 40"))
        XCTAssertTrue(brief.contains("- HRV: 60 ms"))
        XCTAssertTrue(brief.contains("Not available:"))
        XCTAssertTrue(brief.contains("Cardio fitness"), "VO2 max had no reading, so it is listed as missing")
    }

    func test_brief_building_stillListsSignalsFromInputs() {
        let resolved = BioAgeStateResolver.Resolved(
            state: .building(days: 9, requiredDays: 15), chronologicalAge: 40, inputs: inputs
        )

        let brief = BiologyBriefEngine.brief(resolved, unit: .metric)

        XCTAssertTrue(brief.hasPrefix("No Biological Age yet: 9 of 30 days"))
        XCTAssertTrue(brief.contains("- Resting heart rate: 52 bpm"))
    }

    func test_brief_trend_namesFirstAndLastPoints() throws {
        let estimate = try XCTUnwrap(PerformanceAgeEngine.estimate(inputs: inputs))
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let resolved = BioAgeStateResolver.Resolved(
            state: .unlocked(estimate: estimate), chronologicalAge: 40, inputs: inputs,
            trend: [.init(date: start, biologicalAge: 39.0),
                    .init(date: start.addingTimeInterval(7 * 86_400), biologicalAge: 37.5)]
        )

        let brief = BiologyBriefEngine.brief(resolved, unit: .metric)

        XCTAssertTrue(brief.contains("Trend: \(BioAgeFormat.age(39.0)) on"))
        XCTAssertTrue(brief.contains("\(BioAgeFormat.age(37.5)) on"))
    }

    func test_brief_locked_saysNothingIsAvailable() {
        let brief = BiologyBriefEngine.brief(.init(state: .locked, chronologicalAge: 35), unit: .metric)
        XCTAssertTrue(brief.hasPrefix("No Biological Age available."))
    }
}
