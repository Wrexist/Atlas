import Foundation
import OSLog
import StoreKit

private let log = Logger(subsystem: "com.peptidesai.app", category: "StoreService")

@MainActor @Observable
final class StoreService {
    static let shared = StoreService()

    private(set) var isProUser = false
    private(set) var hasActiveTrial = false
    private(set) var trialDaysRemaining: Int = 0
    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var hasLoadedPurchases = false

    static let monthlyID = "com.peptidesai.app.pro.monthly"
    static let annualID = "com.peptidesai.app.pro.annual"
    static let lifetimeID = "com.peptidesai.app.pro.lifetime"

    static let trialDuration: TimeInterval = 3 * 24 * 60 * 60

    private static let trialStartKey = "store.trialStartedAt"
    private static let trialUsedKey = "store.trialUsed"
    private static let offerSeenKey = "store.onboardingOfferSeen"

    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var productsTask: Task<Void, Never>?
    @ObservationIgnored private var trialExpiryTask: Task<Void, Never>?

    private init() {
        recomputeTrial()
        recomputeProAccess()
        scheduleTrialExpiryRefresh()
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
        trialExpiryTask?.cancel()
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            products = try await Product.products(for: [
                Self.monthlyID,
                Self.annualID,
                Self.lifetimeID,
            ])
        } catch {
            log.error("Failed to load products: \(error.localizedDescription, privacy: .public)")
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

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updatePurchasedProducts()
            return true
        case .userCancelled:
            return false
        case .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await updatePurchasedProducts()
    }

    // MARK: - Free Trial

    var hasUsedTrial: Bool {
        UserDefaults.standard.bool(forKey: Self.trialUsedKey)
    }

    var hasSeenOnboardingOffer: Bool {
        UserDefaults.standard.bool(forKey: Self.offerSeenKey)
    }

    /// Eligibility for the welcome 3-day Liquid Glass trial. Once started or
    /// declined, the offer never returns. Stays `false` until the first
    /// entitlement refresh completes so a reinstalling Pro user never briefly
    /// sees the offer before StoreKit reports their purchase.
    var isEligibleForOnboardingTrial: Bool {
        hasLoadedPurchases
            && !hasUsedTrial
            && !hasSeenOnboardingOffer
            && purchasedProductIDs.isEmpty
    }

    @discardableResult
    func startFreeTrial() -> Bool {
        guard !hasUsedTrial else { return false }
        UserDefaults.standard.set(Date(), forKey: Self.trialStartKey)
        UserDefaults.standard.set(true, forKey: Self.trialUsedKey)
        UserDefaults.standard.set(true, forKey: Self.offerSeenKey)
        recomputeTrial()
        recomputeProAccess()
        scheduleTrialExpiryRefresh()
        return true
    }

    func declineOnboardingOffer() {
        UserDefaults.standard.set(true, forKey: Self.offerSeenKey)
    }

    /// Re-evaluates trial validity against wall-clock time. Safe to call from
    /// scene-phase changes so suspended-then-resumed apps don't keep an expired
    /// trial unlocked.
    func refreshTrialIfNeeded() {
        let wasActive = hasActiveTrial
        recomputeTrial()
        if wasActive != hasActiveTrial {
            recomputeProAccess()
        }
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
            if let transaction = try? checkVerified(result) {
                await transaction.finish()
                await updatePurchasedProducts()
            }
        }
    }

    private func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                purchased.insert(transaction.productID)
            }
        }
        purchasedProductIDs = purchased
        hasLoadedPurchases = true
        recomputeTrial()
        recomputeProAccess()
    }

    private func recomputeTrial() {
        guard let started = UserDefaults.standard.object(forKey: Self.trialStartKey) as? Date else {
            hasActiveTrial = false
            trialDaysRemaining = 0
            return
        }
        let remaining = Self.trialDuration - Date().timeIntervalSince(started)
        if remaining > 0 {
            hasActiveTrial = true
            trialDaysRemaining = max(1, Int(ceil(remaining / 86_400)))
        } else {
            hasActiveTrial = false
            trialDaysRemaining = 0
        }
    }

    private func recomputeProAccess() {
        let proIDs: Set<String> = [Self.monthlyID, Self.annualID, Self.lifetimeID]
        let hasPaid = !purchasedProductIDs.isDisjoint(with: proIDs)
        isProUser = hasPaid || hasActiveTrial
    }

    /// Wakes up at trial expiry while the app is in the foreground so Pro
    /// access drops the moment the 3 days are up — without waiting for a
    /// scene-phase change or transaction update.
    private func scheduleTrialExpiryRefresh() {
        trialExpiryTask?.cancel()
        guard let started = UserDefaults.standard.object(forKey: Self.trialStartKey) as? Date else { return }
        let delay = started.addingTimeInterval(Self.trialDuration).timeIntervalSinceNow
        guard delay > 0 else {
            refreshTrialIfNeeded()
            return
        }
        trialExpiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refreshTrialIfNeeded()
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let value):
            return value
        }
    }
}

enum StoreError: Error {
    case failedVerification
}
