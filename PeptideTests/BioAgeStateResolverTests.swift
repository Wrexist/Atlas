import XCTest
@testable import Peptide

/// `BioAgeStateResolver.resolve(...)` is async and reads
/// HealthKitService.shared, which can't be mocked here. The
/// behaviour that can be tested without HealthKit:
///   • the `isPro=false` short-circuit (never touches HealthKit)
///   • the chronologicalAge fallback when nil is passed
///   • the resolved state's Equatable
@MainActor
final class BioAgeStateResolverTests: XCTestCase {

    func test_resolve_freeTier_shortCircuitsToLocked() async {
        let resolved = await BioAgeStateResolver.resolve(
            chronologicalAge: 30,
            weightHistory: [WeightEntry(date: Date(), kg: 80)],
            isPro: false
        )
        XCTAssertEqual(resolved.state, .locked)
        XCTAssertEqual(resolved.chronologicalAge, 30)
    }

    /// Locked never reads HealthKit, so it must carry no inputs or trend
    /// for the page to render signal coverage from.
    func test_resolve_freeTier_carriesNoInputsOrTrend() async {
        let resolved = await BioAgeStateResolver.resolve(
            chronologicalAge: 40,
            sex: .female,
            bodyMassIndex: 23,
            isPro: false
        )
        XCTAssertNil(resolved.inputs)
        XCTAssertTrue(resolved.trend.isEmpty)
    }

    /// The HealthKit read has to reach back far enough for the oldest
    /// trend point's own 30-day window.
    func test_historyDays_coversTrendPlusWindow() {
        XCTAssertGreaterThanOrEqual(BioAgeStateResolver.historyDays,
                                    PerformanceAgeEngine.trendDays + PerformanceAgeEngine.windowDays)
    }

    /// VO2 max has a 90-day window, so its read reaches further back than
    /// the other signals' or the oldest trend point loses most of it.
    func test_vo2HistoryDays_coversTrendPlusVO2Window() {
        XCTAssertGreaterThanOrEqual(BioAgeStateResolver.vo2HistoryDays,
                                    PerformanceAgeEngine.trendDays + PerformanceAgeEngine.vo2WindowDays)
    }

    /// The fallback constant exists so locked-state screenshots
    /// without a configured profile still render meaningful
    /// scale labels (35 ±5 → 30…40 on the dial).
    func test_resolve_freeTierNilAge_usesFallback() async {
        let resolved = await BioAgeStateResolver.resolve(
            chronologicalAge: nil,
            isPro: false
        )
        XCTAssertEqual(resolved.state, .locked)
        XCTAssertEqual(resolved.chronologicalAge, BioAgeStateResolver.chronologicalAgeFallback)
    }

    /// A Pro user who skipped their age must not get an estimate built
    /// against the fallback age.
    func test_resolve_proNilAge_needsAgeNotEstimate() async {
        let resolved = await BioAgeStateResolver.resolve(chronologicalAge: nil, isPro: true)
        XCTAssertEqual(resolved.state, .needsAge)
        XCTAssertNil(resolved.inputs)
    }

    func test_resolve_proUnderMinimumAge_needsAge() async {
        let resolved = await BioAgeStateResolver.resolve(chronologicalAge: 16, isPro: true)
        XCTAssertEqual(resolved.state, .needsAge)
        XCTAssertEqual(resolved.chronologicalAge, 16)
    }

    /// Full coverage at 14 days is still short of the gate, so the
    /// building state must not read as complete.
    func test_buildingState_fullCoverageFourteenDays_isNotComplete() {
        let inputs = PerformanceAgeEngine.Inputs(
            chronologicalAge: 35, hrvMedian30d: 50, rhrMedian30d: 60,
            sleepHoursMedian30d: 7.5, vo2MaxRecent: 40, healthDataDays: 14
        )
        XCTAssertEqual(BioAgeStateResolver.buildingState(for: inputs),
                       .building(days: 14, requiredDays: 15))
        XCTAssertLessThan(BioAgeHeroSection.buildingProgress(days: 14, requiredDays: 15), 1)
    }

    /// When the signals present can never clear the gate, the state says
    /// so instead of counting towards a day that won't unlock anything.
    func test_buildingState_stepsOnly_hasNoDayTarget() {
        let inputs = PerformanceAgeEngine.Inputs(chronologicalAge: 35, stepsMedian30d: 8_000, healthDataDays: 30)
        XCTAssertEqual(BioAgeStateResolver.buildingState(for: inputs),
                       .building(days: 30, requiredDays: nil))
    }

    // MARK: - BioAgeState Equatable

    func test_bioAgeState_equality_acrossCases() {
        XCTAssertEqual(BioAgeHeroSection.BioAgeState.locked,
                       BioAgeHeroSection.BioAgeState.locked)
        XCTAssertNotEqual(BioAgeHeroSection.BioAgeState.locked,
                          BioAgeHeroSection.BioAgeState.building(days: 0, requiredDays: 15))
        XCTAssertEqual(BioAgeHeroSection.BioAgeState.building(days: 5, requiredDays: 15),
                       BioAgeHeroSection.BioAgeState.building(days: 5, requiredDays: 15))
        XCTAssertNotEqual(BioAgeHeroSection.BioAgeState.building(days: 5, requiredDays: 15),
                          BioAgeHeroSection.BioAgeState.building(days: 6, requiredDays: 15))
    }

    func test_bioAgeState_unlocked_equalityComparesByEstimate() {
        let est1 = PerformanceAgeEngine.Estimate(
            biologicalAge: 28.5, confidence: 0.9, drivers: []
        )
        let est2 = PerformanceAgeEngine.Estimate(
            biologicalAge: 28.5, confidence: 0.9, drivers: []
        )
        let est3 = PerformanceAgeEngine.Estimate(
            biologicalAge: 29.0, confidence: 0.9, drivers: []
        )
        XCTAssertEqual(BioAgeHeroSection.BioAgeState.unlocked(estimate: est1),
                       BioAgeHeroSection.BioAgeState.unlocked(estimate: est2))
        XCTAssertNotEqual(BioAgeHeroSection.BioAgeState.unlocked(estimate: est1),
                          BioAgeHeroSection.BioAgeState.unlocked(estimate: est3))
    }

    func test_labDraws_keepsOnlyThatPanel() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let history = [
            LabValue(date: date, panel: .hba1c, value: 5.4),
            LabValue(date: date, panel: .ldl, value: 110),
            LabValue(date: date.addingTimeInterval(86_400), panel: .hba1c, value: 5.6),
        ]
        let draws = BioAgeStateResolver.labDraws(history, panel: .hba1c)
        XCTAssertEqual(draws.map(\.value), [5.4, 5.6])
    }
}

