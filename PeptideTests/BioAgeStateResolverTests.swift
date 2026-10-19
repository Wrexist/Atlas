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
        XCTAssertGreaterThanOrEqual(BioAgeStateResolver.historyDays, 90 + PerformanceAgeEngine.windowDays)
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

    /// The minimum-baseline-days constant gates the Pro-tier
    /// "building" state. Locked here only because we forced
    /// isPro=false; in a real run with isPro=true + no HealthKit
    /// data, the resolver returns .building(progress: 0).
    func test_minBaselineDays_isAtLeastOneWeek() {
        XCTAssertGreaterThanOrEqual(BioAgeStateResolver.minBaselineDays, 7)
    }

    // MARK: - BioAgeState Equatable

    func test_bioAgeState_equality_acrossCases() {
        XCTAssertEqual(BioAgeHeroSection.BioAgeState.locked,
                       BioAgeHeroSection.BioAgeState.locked)
        XCTAssertNotEqual(BioAgeHeroSection.BioAgeState.locked,
                          BioAgeHeroSection.BioAgeState.building(progress: 0))
        XCTAssertEqual(BioAgeHeroSection.BioAgeState.building(progress: 0.5),
                       BioAgeHeroSection.BioAgeState.building(progress: 0.5))
        XCTAssertNotEqual(BioAgeHeroSection.BioAgeState.building(progress: 0.5),
                          BioAgeHeroSection.BioAgeState.building(progress: 0.6))
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
}
