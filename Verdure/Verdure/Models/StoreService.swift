import Foundation
import Observation
import StoreKit

// MARK: - Store Service (Verdure+ subscription via StoreKit 2)
//
// Product IDs must match App Store Connect (and Verdure.storekit for local
// simulator testing — the Verdure scheme points at it):
//   com.vaiybhav.verdure.plus.monthly   $4.99/month
//   com.vaiybhav.verdure.plus.yearly    $49.99/year
//
// NOTE: premium gating is client-side for now. Before real launch, verify the
// subscription server-side too (App Store Server API) so redeemReward can
// enforce Plus-only reward tiers.

@MainActor @Observable
final class StoreService {

    static let monthlyID = "com.vaiybhav.verdure.plus.monthly"
    static let yearlyID = "com.vaiybhav.verdure.plus.yearly"
    private static let allIDs: Set<String> = [monthlyID, yearlyID]

    // MARK: - Published State

    private(set) var products: [Product] = []
    private(set) var purchasedIDs = Set<String>()
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    var lastError: String?

    /// True when the user has an active Verdure+ entitlement.
    var isPlus: Bool { !purchasedIDs.isEmpty }

    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var yearly: Product? { products.first { $0.id == Self.yearlyID } }

    private var updatesTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        // Listen for transactions that happen outside the purchase flow
        // (renewals, Ask to Buy approvals, purchases on other devices).
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    // MARK: - Products

    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: Self.allIDs)
                .sorted { $0.price < $1.price }
        } catch {
            lastError = "Couldn't load subscription options. \(error.localizedDescription)"
        }
    }

    // MARK: - Purchase / Restore

    /// Purchase a subscription. Returns true when the entitlement is active.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        guard !isPurchasing else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        lastError = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "Purchase couldn't be verified."
                    return false
                }
                purchasedIDs.insert(transaction.productID)
                await transaction.finish()
                Haptics.success()
                return true
            case .userCancelled:
                return false
            case .pending:
                lastError = "Purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Re-sync with the App Store (e.g. after reinstalling).
    func restorePurchases() async {
        lastError = nil
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    // MARK: - Entitlements

    func refreshEntitlements() async {
        var owned = Set<String>()
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               Self.allIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                owned.insert(transaction.productID)
            }
        }
        purchasedIDs = owned
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        if case .verified(let transaction) = update {
            await transaction.finish()
            await refreshEntitlements()
        }
    }
}
