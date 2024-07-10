//
//  StorePurchaseManager.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import StoreKit
import Common

public enum StoreError: Error {
    case failedVerification
}

public enum StorePurchaseManagerError: Error {
    case productNotFound
    case externalIDisNotAValidUUID
    case purchaseFailed
    case transactionCannotBeVerified
    case transactionPendingAuthentication
    case purchaseCancelledByUser
    case unknownError
}

public protocol StorePurchaseManager {
    typealias TransactionJWS = String
    func subscriptionOptions() async -> SubscriptionOptions?
    var purchasedProductIDs: [String] { get }
    var purchaseQueue: [String] { get }
    var areProductsAvailable: Bool { get }
    @MainActor func syncAppleIDAccount() async throws
    @MainActor func updateAvailableProducts() async
    @MainActor func updatePurchasedProducts() async
    @MainActor func mostRecentTransaction() async -> String?
    @MainActor func hasActiveSubscription() async -> Bool
    @MainActor func purchaseSubscription(with identifier: String, externalID: String) async -> Result<StorePurchaseManager.TransactionJWS, StorePurchaseManagerError>
}

@available(macOS 12.0, iOS 15.0, *) typealias Transaction = StoreKit.Transaction
@available(macOS 12.0, iOS 15.0, *) typealias RenewalInfo = StoreKit.Product.SubscriptionInfo.RenewalInfo
@available(macOS 12.0, iOS 15.0, *) typealias RenewalState = StoreKit.Product.SubscriptionInfo.RenewalState

@available(macOS 12.0, iOS 15.0, *)
public final class DefaultStorePurchaseManager: ObservableObject, StorePurchaseManager {

    let productIdentifiers = ["ios.subscription.1month", "ios.subscription.1year",
                              "subscription.1month", "subscription.1year",
                              "review.subscription.1month", "review.subscription.1year",
                              "tf.sandbox.subscription.1month", "tf.sandbox.subscription.1year",
                              "ddg.privacy.pro.monthly.renews.us", "ddg.privacy.pro.yearly.renews.us"]

    @Published public private(set) var availableProducts: [Product] = []
    @Published public private(set) var purchasedProductIDs: [String] = []
    @Published public private(set) var purchaseQueue: [String] = []
    @Published private var subscriptionGroupStatus: RenewalState?

    public var areProductsAvailable: Bool {
        !availableProducts.isEmpty
    }

    private var transactionUpdates: Task<Void, Never>?
    private var storefrontChanges: Task<Void, Never>?

    public init() {
        transactionUpdates = observeTransactionUpdates()
        storefrontChanges = observeStorefrontChanges()
    }

    deinit {
        transactionUpdates?.cancel()
        storefrontChanges?.cancel()
    }

    @MainActor
    public func syncAppleIDAccount() async throws {
        do {
            purchaseQueue.removeAll()

            os_log(.info, log: .subscription, "[StorePurchaseManager] Before AppStore.sync()")

            try await AppStore.sync()

            os_log(.info, log: .subscription, "[StorePurchaseManager] After AppStore.sync()")

            await updatePurchasedProducts()
            await updateAvailableProducts()
        } catch {
            os_log(.error, log: .subscription, "[StorePurchaseManager] Error: %{public}s (%{public}s)", String(reflecting: error), error.localizedDescription)
            throw error
        }
    }

    public func subscriptionOptions() async -> SubscriptionOptions? {
        os_log(.info, log: .subscription, "[AppStorePurchaseFlow] subscriptionOptions")
        let products = availableProducts
        let monthly = products.first(where: { $0.subscription?.subscriptionPeriod.unit == .month && $0.subscription?.subscriptionPeriod.value == 1 })
        let yearly = products.first(where: { $0.subscription?.subscriptionPeriod.unit == .year && $0.subscription?.subscriptionPeriod.value == 1 })
        guard let monthly, let yearly else {
            os_log(.error, log: .subscription, "[AppStorePurchaseFlow] No products found")
            return nil
        }

        let options = [SubscriptionOption(id: monthly.id, cost: .init(displayPrice: monthly.displayPrice, recurrence: "monthly")),
                       SubscriptionOption(id: yearly.id, cost: .init(displayPrice: yearly.displayPrice, recurrence: "yearly"))]
        let features = SubscriptionFeatureName.allCases.map { SubscriptionFeature(name: $0.rawValue) }
        let platform: SubscriptionPlatformName

#if os(iOS)
        platform = .ios
#else
        platform = .macos
#endif
        return SubscriptionOptions(platform: platform.rawValue,
                                   options: options,
                                   features: features)
    }

    @MainActor
    public func updateAvailableProducts() async {
        os_log(.info, log: .subscription, "[StorePurchaseManager] updateAvailableProducts")

        do {
            let availableProducts = try await Product.products(for: productIdentifiers)
            os_log(.info, log: .subscription, "[StorePurchaseManager] updateAvailableProducts fetched %d products", availableProducts.count)

            if self.availableProducts != availableProducts {
                self.availableProducts = availableProducts
            }
        } catch {
            os_log(.error, log: .subscription, "[StorePurchaseManager] Error: %{public}s", String(reflecting: error))
        }
    }

    @MainActor
    public func updatePurchasedProducts() async {
        os_log(.info, log: .subscription, "[StorePurchaseManager] updatePurchasedProducts")

        var purchasedSubscriptions: [String] = []

        do {
            for await result in Transaction.currentEntitlements {
                let transaction = try checkVerified(result)

                guard transaction.productType == .autoRenewable else { continue }
                guard transaction.revocationDate == nil else { continue }

                if let expirationDate = transaction.expirationDate, expirationDate > .now {
                    purchasedSubscriptions.append(transaction.productID)
                }
            }
        } catch {
            os_log(.error, log: .subscription, "[StorePurchaseManager] Error: %{public}s", String(reflecting: error))
        }

        os_log(.info, log: .subscription, "[StorePurchaseManager] updatePurchasedProducts fetched %d active subscriptions", purchasedSubscriptions.count)

        if self.purchasedProductIDs != purchasedSubscriptions {
            self.purchasedProductIDs = purchasedSubscriptions
        }

        subscriptionGroupStatus = try? await availableProducts.first?.subscription?.status.first?.state
    }

    @MainActor
    public func mostRecentTransaction() async -> String? {
        os_log(.info, log: .subscription, "[StorePurchaseManager] mostRecentTransaction")

        var transactions: [VerificationResult<Transaction>] = []

        for await result in Transaction.all {
            transactions.append(result)
        }

        os_log(.info, log: .subscription, "[StorePurchaseManager] mostRecentTransaction fetched %d transactions", transactions.count)

        return transactions.first?.jwsRepresentation
    }

    @MainActor
    public func hasActiveSubscription() async -> Bool {
        os_log(.info, log: .subscription, "[StorePurchaseManager] hasActiveSubscription")

        var transactions: [VerificationResult<Transaction>] = []

        for await result in Transaction.currentEntitlements {
            transactions.append(result)
        }

        os_log(.info, log: .subscription, "[StorePurchaseManager] hasActiveSubscription fetched %d transactions", transactions.count)

        return !transactions.isEmpty
    }

    @MainActor
    public func purchaseSubscription(with identifier: String, externalID: String) async -> Result<TransactionJWS, StorePurchaseManagerError> {

        guard let product = availableProducts.first(where: { $0.id == identifier }) else { return .failure(StorePurchaseManagerError.productNotFound) }

        os_log(.info, log: .subscription, "[StorePurchaseManager] purchaseSubscription %{public}s (%{public}s)", product.displayName, externalID)

        purchaseQueue.append(product.id)

        var options: Set<Product.PurchaseOption> = Set()

        if let token = UUID(uuidString: externalID) {
            options.insert(.appAccountToken(token))
        } else {
            os_log(.error, log: .subscription, "[StorePurchaseManager] Error: Failed to create UUID")
            return .failure(StorePurchaseManagerError.externalIDisNotAValidUUID)
        }

        let purchaseResult: Product.PurchaseResult
        do {
            purchaseResult = try await product.purchase(options: options)
        } catch {
            os_log(.error, log: .subscription, "[StorePurchaseManager] Error: %{public}s", String(reflecting: error))
            return .failure(StorePurchaseManagerError.purchaseFailed)
        }

        os_log(.info, log: .subscription, "[StorePurchaseManager] purchaseSubscription complete")

        purchaseQueue.removeAll()

        switch purchaseResult {
        case let .success(verificationResult):
            switch verificationResult {
            case let .verified(transaction):
                os_log(.info, log: .subscription, "[StorePurchaseManager] purchaseSubscription result: success")
                // Successful purchase
                await transaction.finish()
                await self.updatePurchasedProducts()
                return .success(verificationResult.jwsRepresentation)
            case let .unverified(_, error):
                os_log(.info, log: .subscription, "[StorePurchaseManager] purchaseSubscription result: success /unverified/ - %{public}s", String(reflecting: error))
                // Successful purchase but transaction/receipt can't be verified
                // Could be a jailbroken phone
                return .failure(StorePurchaseManagerError.transactionCannotBeVerified)
            }
        case .pending:
            os_log(.info, log: .subscription, "[StorePurchaseManager] purchaseSubscription result: pending")
            // Transaction waiting on SCA (Strong Customer Authentication) or
            // approval from Ask to Buy
            return .failure(StorePurchaseManagerError.transactionPendingAuthentication)
        case .userCancelled:
            os_log(.info, log: .subscription, "[StorePurchaseManager] purchaseSubscription result: user cancelled")
            return .failure(StorePurchaseManagerError.purchaseCancelledByUser)
        @unknown default:
            os_log(.info, log: .subscription, "[StorePurchaseManager] purchaseSubscription result: unknown")
            return .failure(StorePurchaseManagerError.unknownError)
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        // Check whether the JWS passes StoreKit verification.
        switch result {
        case .unverified:
            // StoreKit parses the JWS, but it fails verification.
            throw StoreError.failedVerification
        case .verified(let safe):
            // The result is verified. Return the unwrapped value.
            return safe
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {

        Task.detached { [weak self] in
            for await result in Transaction.updates {
                os_log(.info, log: .subscription, "[StorePurchaseManager] observeTransactionUpdates")

                if case .verified(let transaction) = result {
                    await transaction.finish()
                }

                await self?.updatePurchasedProducts()
            }
        }
    }

    private func observeStorefrontChanges() -> Task<Void, Never> {

        Task.detached { [weak self] in
            for await result in Storefront.updates {
                os_log(.info, log: .subscription, "[StorePurchaseManager] observeStorefrontChanges: %s", result.countryCode)
                await self?.updatePurchasedProducts()
                await self?.updateAvailableProducts()
            }
        }
    }
}
