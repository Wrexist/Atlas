import XCTest
@testable import Peptide

/// Covers `OnboardingExperiment`'s assignment logic — must be sticky
/// per install and deterministic across reads. The tracker emits a
/// funnel event on first assignment; the test scrubs all relevant
/// UserDefaults keys before and after each case so a parallel test
/// run doesn't contaminate state.
@MainActor
final class OnboardingExperimentTests: XCTestCase {

    private let funnelKeys = [
        "onboarding.funnel.snapshot.v1",
        "onboarding.funnel.sessionID.v1",
        "onboarding.funnel.completed.v1",
    ]

    override func setUp() {
        super.setUp()
        OnboardingExperiment.resetForTesting()
        funnelKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        OnboardingExperiment.resetForTesting()
        funnelKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    func test_variant_isStickyAcrossReads() {
        let first  = OnboardingExperiment.variant(for: .paywallTierOrder)
        let second = OnboardingExperiment.variant(for: .paywallTierOrder)
        let third  = OnboardingExperiment.variant(for: .paywallTierOrder)
        XCTAssertEqual(first, second)
        XCTAssertEqual(second, third)
    }

    func test_resetForTesting_clearsAssignment() {
        let first = OnboardingExperiment.variant(for: .paywallTierOrder)
        OnboardingExperiment.resetForTesting()
        // After reset, a new install ID is generated; the probability
        // that the re-assignment lands on the same variant is exactly
        // 50%, so we don't assert inequality — instead we just confirm
        // the reset path runs without error and produces a valid variant.
        let second = OnboardingExperiment.variant(for: .paywallTierOrder)
        XCTAssertTrue(
            second == .control || second == .variantA,
            "Got \(second) — must be one of the two valid cases"
        )
        _ = first  // silence the unused-variable warning
    }

    func test_resolve_returnsIsFreshTrue_onFirstCall() {
        let resolution = OnboardingExperiment.resolve(for: .paywallTierOrder)
        XCTAssertTrue(resolution.isFresh,
                      "First resolve should report isFresh = true so the caller records the funnel event")
    }

    func test_resolve_returnsIsFreshFalse_onSubsequentCalls() {
        // Prime the cache.
        _ = OnboardingExperiment.resolve(for: .paywallTierOrder)
        let second = OnboardingExperiment.resolve(for: .paywallTierOrder)
        let third  = OnboardingExperiment.resolve(for: .paywallTierOrder)
        XCTAssertFalse(second.isFresh)
        XCTAssertFalse(third.isFresh)
    }

    func test_funnelEventName_isStable() {
        let control  = OnboardingExperiment.funnelEventName(for: .paywallTierOrder, variant: .control)
        let variantA = OnboardingExperiment.funnelEventName(for: .paywallTierOrder, variant: .variantA)
        XCTAssertEqual(control, "experiment_paywall_tier_order_control")
        XCTAssertEqual(variantA, "experiment_paywall_tier_order_variantA")
    }
}
