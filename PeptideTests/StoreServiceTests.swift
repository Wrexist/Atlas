import XCTest
import StoreKit
import StoreKitTest
@testable import Peptide

/// Tests for `StoreService` driven by `SKTestSession` against the
/// project's bundled `Products.storekit` config. Each test resets the
/// session's transaction state and re-reads entitlements so the
/// singleton's `isProUser` flag starts from a clean slate.
///
/// What's covered:
/// - Product loading by ID (monthly / annual / lifetime resolve)
/// - Trial-display formatting (P7D → "7 days free") and the
///   eligibility gate that stops the paywall promising a redeemed trial
/// - Purchase round-trip: monthly subscription updates `isProUser` and
///   the `purchasedProductIDs` set
/// - Lifetime non-consumable purchase also flips `isProUser`
/// - Restore from a clean session produces no entitlement
/// - `requiresPro` gating logic vs the active-protocol count
/// - The `canAccess*` getters mirror `isProUser`
///
/// What's not covered: the `Transaction.updates` listener (an
/// `AsyncSequence` that can't be deterministically driven from a
/// single test without re-architecting the service), and the
/// `failedVerification` branch (would need the storekit
/// configuration's _failTransactionsEnabled toggled, which is a
/// project-wide setting that's not test-isolated).
@MainActor
final class StoreServiceTests: XCTestCase {

    private var session: SKTestSession!
    private var service: StoreService!

    override func setUp() async throws {
        try await super.setUp()
        session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true
        session.clearTransactions()
        // Reset the test storefront to USA so price strings are
        // deterministic — the .storekit file defaults to USA but a
        // prior test could have changed it.
        session.storefront = "USA"
        // Belt-and-suspenders: clear any locally-cached entitlement
        // state on the singleton before each test.
        service = StoreService.shared
        await service.checkProAccess()
    }

    override func tearDown() async throws {
        session.clearTransactions()
        session = nil
        // Re-read entitlements so the next test sees a non-Pro user.
        await service.checkProAccess()
        service = nil
        try await super.tearDown()
    }

    // MARK: - Product loading

    func test_loadProducts_resolvesAllThreeTiers() async {
        await service.loadProducts()
        XCTAssertNotNil(service.monthlyProduct, "Monthly subscription must resolve from the .storekit file")
        XCTAssertNotNil(service.annualProduct,  "Annual subscription must resolve from the .storekit file")
        XCTAssertNotNil(service.lifetimeProduct, "Lifetime non-consumable must resolve from the .storekit file")
    }

    func test_loadProducts_assignsCorrectProductIDs() async {
        await service.loadProducts()
        XCTAssertEqual(service.monthlyProduct?.id, StoreService.monthlyID)
        XCTAssertEqual(service.annualProduct?.id, StoreService.annualID)
        XCTAssertEqual(service.lifetimeProduct?.id, StoreService.lifetimeID)
    }

    // MARK: - Trial display

    func test_monthlyTrialDisplay_formatsP7D_asSevenDaysFree() async {
        await service.loadProducts()
        XCTAssertEqual(service.monthlyTrialDisplay, "7 days free")
    }

    func test_annualTrialDisplay_formatsP7D_asSevenDaysFree() async {
        // Both plans launch with the same 7-day trial, so the annual row
        // must advertise it too — it used to read "Billed $49.99/yr" with
        // no mention of the trial the user was actually getting.
        await service.loadProducts()
        XCTAssertEqual(service.annualTrialDisplay, "7 days free")
    }

    func test_trialDays_returnsSeven_forBothSubscriptions() async {
        await service.loadProducts()
        XCTAssertEqual(StoreService.trialDays(for: service.monthlyProduct), 7)
        XCTAssertEqual(StoreService.trialDays(for: service.annualProduct), 7)
    }

    func test_trialDays_isNil_forLifetime_whichHasNoIntroOffer() async {
        // The paywall drives its "$0.00 today" copy off this. A non-nil
        // answer here would put a free-trial promise on a one-time
        // purchase, which is a 3.1.2(a) accuracy problem.
        await service.loadProducts()
        XCTAssertNil(StoreService.trialDays(for: service.lifetimeProduct))
    }

    func test_isEligibleForTrial_isFalse_forLifetime() async {
        await service.loadProducts()
        guard let lifetime = service.lifetimeProduct else {
            XCTFail("lifetime product missing — .storekit not loaded?")
            return
        }
        XCTAssertFalse(service.isEligibleForTrial(lifetime))
        XCTAssertNil(service.redeemableTrialDays(for: lifetime))
    }

    func test_redeemableTrialDays_isNil_onceTheTrialIsRedeemed() async throws {
        // Monthly and annual share a subscription group, so buying either
        // one burns the intro offer for both. The CTA must stop saying
        // "free" at that point rather than charging someone a price the
        // button told them was zero.
        await service.loadProducts()
        guard let monthly = service.monthlyProduct,
              let annual = service.annualProduct
        else {
            XCTFail("subscription products missing — .storekit not loaded?")
            return
        }
        try await service.purchase(monthly)

        XCTAssertNil(service.redeemableTrialDays(for: monthly))
        XCTAssertNil(service.redeemableTrialDays(for: annual))
    }

    // MARK: - Purchase round-trip

    func test_purchase_monthly_setsIsProUser() async throws {
        await service.loadProducts()
        guard let monthly = service.monthlyProduct else {
            XCTFail("monthly product missing — .storekit not loaded?")
            return
        }
        let succeeded = try await service.purchase(monthly)
        XCTAssertTrue(succeeded)
        XCTAssertTrue(service.isProUser, "Purchasing the monthly tier must flip isProUser to true")
        XCTAssertTrue(service.purchasedProductIDs.contains(StoreService.monthlyID))
    }

    func test_purchase_lifetime_setsIsProUser() async throws {
        await service.loadProducts()
        guard let lifetime = service.lifetimeProduct else {
            XCTFail("lifetime product missing")
            return
        }
        let succeeded = try await service.purchase(lifetime)
        XCTAssertTrue(succeeded)
        XCTAssertTrue(service.isProUser, "Lifetime non-consumable must flip isProUser")
        XCTAssertTrue(service.purchasedProductIDs.contains(StoreService.lifetimeID))
    }

    func test_startMonthlyTrial_succeeds_whenProductLoaded() async throws {
        await service.loadProducts()
        let started = try await service.startMonthlyTrial()
        XCTAssertTrue(started)
        XCTAssertTrue(service.isProUser)
    }

    func test_startMonthlyTrial_returnsFalse_whenProductNotLoaded() async throws {
        // "Don't call loadProducts" was not enough on its own: the
        // service is a process-lifetime singleton, so any earlier test
        // that loaded the catalogue left it loaded here and this test
        // actually completed a purchase — failing both assertions below
        // for a reason that had nothing to do with the guard.
        service.resetLoadedProductsForTesting()
        XCTAssertNil(service.monthlyProduct, "precondition: the catalogue must be empty")

        let started = try await service.startMonthlyTrial()
        XCTAssertFalse(started)
        XCTAssertFalse(service.isProUser)
    }

    // MARK: - Entitlement state

    func test_isProUser_isFalse_onCleanSession() async {
        // setUp already cleared transactions and called checkProAccess
        // — the singleton should be reading "no entitlements".
        XCTAssertFalse(service.isProUser)
        XCTAssertTrue(service.purchasedProductIDs.isEmpty)
    }

    func test_canAccessAIFeatures_mirrorsIsProUser() async throws {
        // The one per-feature flag the app enforces (the Pro weekly
        // recap). Its five never-read siblings were removed; asserting
        // that an unused alias of `isProUser` equals `isProUser` was the
        // only thing keeping them alive.
        XCTAssertFalse(service.canAccessAIFeatures)

        await service.loadProducts()
        guard let monthly = service.monthlyProduct else { return XCTFail("monthly missing") }
        _ = try await service.purchase(monthly)

        XCTAssertTrue(service.canAccessAIFeatures)
    }

    // MARK: - Active-protocol gating

    func test_requiresPro_isFalse_belowFreeTierThreshold_whenNotPro() {
        // Free tier allows up to 2 active protocols. Adding a third
        // is what triggers the upsell.
        XCTAssertFalse(service.requiresPro(activeProtocolCount: 0))
        XCTAssertFalse(service.requiresPro(activeProtocolCount: 1))
        XCTAssertFalse(service.requiresPro(activeProtocolCount: 2))
    }

    func test_requiresPro_isTrue_atOrAboveThreshold_whenNotPro() {
        XCTAssertTrue(service.requiresPro(activeProtocolCount: 3))
        XCTAssertTrue(service.requiresPro(activeProtocolCount: 10))
    }

    func test_requiresPro_isFalse_atOrAboveThreshold_whenPro() async throws {
        await service.loadProducts()
        guard let monthly = service.monthlyProduct else { return XCTFail("monthly missing") }
        _ = try await service.purchase(monthly)
        XCTAssertFalse(service.requiresPro(activeProtocolCount: 3))
        XCTAssertFalse(service.requiresPro(activeProtocolCount: 100))
    }

    // MARK: - Restore

    func test_restorePurchases_onCleanSession_leavesNonPro() async throws {
        try await service.restorePurchases()
        XCTAssertFalse(service.isProUser)
        XCTAssertTrue(service.purchasedProductIDs.isEmpty)
    }

    func test_restorePurchases_recoversExistingEntitlement() async throws {
        // Buy lifetime, drop the in-memory entitlement set (without
        // clearing the session), then restore. The session retains
        // the purchase, so restore should bring isProUser back.
        await service.loadProducts()
        guard let lifetime = service.lifetimeProduct else { return XCTFail("lifetime missing") }
        _ = try await service.purchase(lifetime)
        XCTAssertTrue(service.isProUser)

        try await service.restorePurchases()
        XCTAssertTrue(service.isProUser, "Restore must surface the existing lifetime purchase")
        XCTAssertTrue(service.purchasedProductIDs.contains(StoreService.lifetimeID))
    }
}
