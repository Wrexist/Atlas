import XCTest
@testable import Peptide

final class OnboardingRecommendationEngineTests: XCTestCase {

    private var database: [Peptide]!

    override func setUp() {
        super.setUp()
        database = MockPeptides.all
    }

    override func tearDown() {
        database = nil
        super.tearDown()
    }

    // MARK: - Goal coverage

    func test_recommend_returnsEmpty_whenNoGoals() {
        let result = OnboardingRecommendationEngine.recommend(
            goals: [],
            from: database
        )
        XCTAssertTrue(result.isEmpty)
    }

    func test_recommend_returnsRecoveryPeptidesForRecoveryGoal() {
        let result = OnboardingRecommendationEngine.recommend(
            goals: ["Muscle Recovery"],
            from: database
        )
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(
            result.contains { $0.peptide.category == .recovery || $0.peptide.category == .growth },
            "Muscle Recovery should match recovery or growth peptides"
        )
    }

    func test_recommend_handlesSleepGoal() {
        let result = OnboardingRecommendationEngine.recommend(
            goals: ["Better Sleep"],
            from: database
        )
        XCTAssertFalse(result.isEmpty, "Better Sleep should produce at least one match")
    }

    func test_recommend_handlesStressGoal() {
        let result = OnboardingRecommendationEngine.recommend(
            goals: ["Stress Reduction"],
            from: database
        )
        XCTAssertFalse(result.isEmpty, "Stress Reduction should map to cognitive peptides")
    }

    func test_recommend_handlesCognitiveEdgeWording() {
        let result = OnboardingRecommendationEngine.recommend(
            goals: ["Cognitive Edge"],
            from: database
        )
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains { $0.peptide.category == .cognitive })
    }

    // MARK: - Diversification

    func test_recommend_capsAtOnePeptidePerCategory() {
        let result = OnboardingRecommendationEngine.recommend(
            goals: ["Muscle Recovery", "Cognitive Edge", "Anti-Aging", "Fat Loss"],
            from: database,
            limit: 4
        )
        let categories = result.map(\.peptide.category)
        XCTAssertEqual(Set(categories).count, categories.count, "Each category should appear at most once")
    }

    func test_recommend_respectsLimit() {
        let result = OnboardingRecommendationEngine.recommend(
            goals: ["Muscle Recovery", "Cognitive Edge", "Anti-Aging", "Fat Loss"],
            from: database,
            limit: 2
        )
        XCTAssertLessThanOrEqual(result.count, 2)
    }

    // MARK: - Suggestion shape

    func test_suggestion_carriesPeptideAndRationale() {
        let result = OnboardingRecommendationEngine.recommend(
            goals: ["Anti-Aging"],
            from: database
        )
        guard let first = result.first else {
            XCTFail("Expected at least one suggestion")
            return
        }
        XCTAssertFalse(first.peptide.abbreviation.isEmpty)
    }
}
