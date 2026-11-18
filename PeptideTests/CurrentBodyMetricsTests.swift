import XCTest
@testable import Peptide

final class CurrentBodyMetricsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func profile(weighIns: [(daysAgo: Double, kg: Double)]) -> UserProfile {
        var profile = UserProfile.fresh
        profile.bodyMetrics = BodyMetrics(
            weightKg: 90, heightCm: 180, age: 30, sex: .male, activityLevel: .moderate, unit: .metric
        )
        profile.weightHistory = weighIns.map {
            WeightEntry(date: now.addingTimeInterval(-$0.daysAgo * 86_400), kg: $0.kg)
        }
        return profile
    }

    func test_recentWeighIn_replacesOnboardingWeight() {
        let metrics = LifestyleDataLogic.currentBodyMetrics(profile(weighIns: [(10, 84), (1, 80)]), now: now)
        XCTAssertEqual(metrics.weightKg, 80)
    }

    func test_newerWeighIn_changesRecommendedProtein() throws {
        let onboarding = try XCTUnwrap(NutritionMath.recommendedTargets(
            for: LifestyleDataLogic.currentBodyMetrics(profile(weighIns: []), now: now), goalRaw: nil))
        let afterCut = try XCTUnwrap(NutritionMath.recommendedTargets(
            for: LifestyleDataLogic.currentBodyMetrics(profile(weighIns: [(1, 80)]), now: now), goalRaw: nil))
        XCTAssertLessThan(afterCut.proteinG, onboarding.proteinG)
    }

    func test_weighInOlderThanWindow_keepsStoredWeight() {
        let metrics = LifestyleDataLogic.currentBodyMetrics(profile(weighIns: [(45, 80)]), now: now)
        XCTAssertEqual(metrics.weightKg, 90)
    }
}
