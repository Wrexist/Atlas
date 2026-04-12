import Foundation
import StoreKit

@MainActor @Observable
final class StoreService {
    static let shared = StoreService()

    private(set) var isProUser = false
    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []

    static let monthlyID = "com.peptidesai.app.pro.monthly"
    static let annualID = "com.peptidesai.app.pro.annual"

    private nonisolated(unsafe) var updateTask: Task<Void, Never>?

    private init() {
        updateTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
        Task { [weak self] in
            await self?.updatePurchasedProducts()
        }
    }

    deinit {
        updateTask?.cancel()
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            products = try await Product.products(for: [
                Self.monthlyID,
                Self.annualID,
            ])
        } catch {
            print("StoreService: Failed to load products: \(error)")
        }
    }

    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyID }
    }

    var annualProduct: Product? {
        products.first { $0.id == Self.annualID }
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

    func restorePurchases() async {
        try? await AppStore.sync()
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
        isProUser = !purchased.isEmpty
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
