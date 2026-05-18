import Foundation
import StoreKit

@MainActor @Observable
final class StoreService {
    static let shared = StoreService()

    private(set) var isProUser = false
    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    /// Intro-offer eligibility for the monthly subscription. Driven by
    /// `Product.SubscriptionInfo.isEligibleForIntroOffer` — once the user has
    /// already redeemed an intro offer in this subscription group, Apple
    /// reports `false` and the local check matches.
    ///
    /// Note: monthly and annual share a subscription group, so eligibility
    /// is shared — once a user redeems either trial, both flags go false.
    private(set) var isEligibleForMonthlyTrial = true
    private(set) var isEligibleForAnnualTrial = true

    static let monthlyID = "com.peptidesai.app.pro.monthly"
    static let annualID = "com.peptidesai.app.pro.annual"
    static let lifetimeID = "com.peptidesai.app.pro.lifetime"

    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var productsTask: Task<Void, Never>?

    private init() {
        updateTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
        productsTask = Task { [weak self] in
            await self?.updatePurchasedProducts()
        }
    }

    deinit {
        updateTask?.cancel()
        productsTask?.cancel()
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            products = try await Product.products(for: [
                Self.monthlyID,
                Self.annualID,
                Self.lifetimeID,
            ])
            await refreshTrialEligibility()
        } catch {
            AppLog.storeKit.error("Failed to load products: \(error.localizedDescription, privacy: .public)")
        }
    }

    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyID }
    }

    var annualProduct: Product? {
        products.first { $0.id == Self.annualID }
    }

    var lifetimeProduct: Product? {
        products.first { $0.id == Self.lifetimeID }
    }

    /// Display string for the monthly intro offer ("3 days free"). `nil` when
    /// there is no intro offer or the product hasn't loaded yet.
    var monthlyTrialDisplay: String? { trialDisplay(for: monthlyProduct) }

    /// Display string for the annual intro offer ("14 days free"). Surfaced
    /// as a "Best value · 14 days free" badge on slot 10. `nil` when no
    /// intro offer is configured or the product hasn't loaded yet.
    var annualTrialDisplay: String? { trialDisplay(for: annualProduct) }

    private func trialDisplay(for product: Product?) -> String? {
        guard let intro = product?.subscription?.introductoryOffer,
              intro.paymentMode == .freeTrial
        else { return nil }
        let unit = intro.period.unit
        let count = intro.period.value * intro.periodCount
        switch unit {
        case .day: return count == 1 ? "1 day free" : "\(count) days free"
        case .week:
            // "2 weeks free" reads worse on a paywall than "14 days free"
            // even though they're the same length. Prefer days for ≤4
            // weeks so it parses as a recognisable trial length.
            let days = count * 7
            return count <= 4 ? "\(days) days free" : "\(count) weeks free"
        case .month: return count == 1 ? "1 month free" : "\(count) months free"
        case .year: return count == 1 ? "1 year free" : "\(count) years free"
        @unknown default: return nil
        }
    }

    // MARK: - Purchase

    enum PurchaseOutcome: Equatable, Sendable {
        case success
        case userCancelled
        /// "Ask to Buy" — the parent needs to approve. Apple's
        /// recommended pattern is to tell the user the request was
        /// submitted; previously this was indistinguishable from a
        /// no-op (audit Library P0.5).
        case pending
    }

    /// Detailed purchase result. Use this from new code; the legacy
    /// `Bool`-returning shim below is kept for back-compat with
    /// existing call sites and returns `true` only on `.success`.
    func purchaseWithOutcome(_ product: Product) async throws -> PurchaseOutcome {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updatePurchasedProducts()
            return .success
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .userCancelled
        }
    }

    @discardableResult
    func purchase(_ product: Product) async throws -> Bool {
        try await purchaseWithOutcome(product) == .success
    }

    /// Starts the monthly subscription, which auto-applies the configured
    /// 3-day free trial intro offer when the user is eligible. After the
    /// trial Apple auto-renews monthly until the user cancels.
    @discardableResult
    func startMonthlyTrial() async throws -> Bool {
        guard let monthly = monthlyProduct else { return false }
        return try await purchase(monthly)
    }

    func restorePurchases() async throws {
        do {
            try await AppStore.sync()
        } catch {
            AppLog.storeKit.error("AppStore.sync failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        await updatePurchasedProducts()
    }

    // MARK: - Entitlement Checking

    func checkProAccess() async {
        await updatePurchasedProducts()
    }

    var canAccessUnlimitedProtocols: Bool { isProUser }
    var canAccessFullAnalytics: Bool { isProUser }
    var canAccessAIFeatures: Bool { isProUser }
    var canAccessCloudSync: Bool { isProUser }
    var canAccessExport: Bool { isProUser }
    var canAccessAllWidgets: Bool { isProUser }

    func requiresPro(activeProtocolCount: Int) -> Bool {
        !isProUser && activeProtocolCount >= 3
    }

    // MARK: - Private

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            do {
                let transaction = try checkVerified(result)
                await transaction.finish()
                await updatePurchasedProducts()
            } catch {
                AppLog.storeKit.error("Transaction.updates verification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                purchased.insert(transaction.productID)
            } catch {
                AppLog.storeKit.error("Entitlement verification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        let proIDs: Set<String> = [Self.monthlyID, Self.annualID, Self.lifetimeID]
        purchasedProductIDs = purchased
        isProUser = !purchased.isDisjoint(with: proIDs)
        await refreshTrialEligibility()
    }

    private func refreshTrialEligibility() async {
        if let monthly = monthlyProduct?.subscription {
            isEligibleForMonthlyTrial = await monthly.isEligibleForIntroOffer
        } else {
            isEligibleForMonthlyTrial = false
        }
        if let annual = annualProduct?.subscription {
            isEligibleForAnnualTrial = await annual.isEligibleForIntroOffer
        } else {
            isEligibleForAnnualTrial = false
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(let value, let verificationError):
            let productID = (value as? Transaction)?.productID ?? "unknown"
            AppLog.storeKit.error("Verification failed for product \(productID, privacy: .public): \(verificationError.localizedDescription, privacy: .public)")
            throw StoreError.failedVerification
        case .verified(let value):
            return value
        }
    }
}

enum StoreError: Error {
    case failedVerification
}
