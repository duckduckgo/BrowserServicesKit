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
import os.log

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

/// A protocol that defines the properties of an introductory offer for a subscription product.
/// Use this protocol to represent trial periods, introductory prices, or other special offers.
@available(macOS 12.0, iOS 15.0, *)
public protocol SubscriptionProductIntroductoryOffer {
    /// The unique identifier of the introductory offer.
    var id: String? { get }

    /// The formatted price of the offer that should be displayed to users.
    var displayPrice: String { get }

    /// The duration of the offer in days.
    var periodInDays: Int { get }

    /// Indicates whether this offer represents a free trial period.
    var isFreeTrial: Bool { get }
}

/// Extends StoreKit's Product.SubscriptionOffer to conform to SubscriptionProductIntroductoryOffer.
@available(macOS 12.0, iOS 15.0, *)
extension Product.SubscriptionOffer: SubscriptionProductIntroductoryOffer {
    /// Calculates the total number of days in the offer period by multiplying
    /// the base period length by the period count.
    public var periodInDays: Int {
        period.periodInDays * periodCount
    }

    /// Determines if this offer represents a free trial based on the payment mode.
    public var isFreeTrial: Bool {
        paymentMode == .freeTrial
    }
}

/// A protocol that defines the core functionality and properties of a subscription product.
/// Conforming types must provide information about pricing, description, and subscription terms.
@available(macOS 12.0, iOS 15.0, *)
public protocol SubscriptionProduct: Equatable {
    /// The unique identifier of the product.
    var id: String { get }

    /// The user-facing name of the product.
    var displayName: String { get }

    /// The formatted price that should be displayed to users.
    var displayPrice: String { get }

    /// A detailed description of the product.
    var description: String { get }

    /// Indicates whether this is a monthly subscription.
    var isMonthly: Bool { get }

    /// Indicates whether this is a yearly subscription.
    var isYearly: Bool { get }

    /// The introductory offer associated with this subscription, if any.
    var introductoryOffer: SubscriptionProductIntroductoryOffer? { get }

    /// Indicates whether this subscription has a Free Trial offer available.
    var hasFreeTrialOffer: Bool { get }

    /// Asynchronously determines whether the user is eligible for an introductory offer.
    var isEligibleForIntroOffer: Bool { get async }

    /// Initiates a purchase of the subscription with the specified options.
    /// - Parameter options: A set of options to configure the purchase.
    /// - Returns: The result of the purchase attempt.
    /// - Throws: An error if the purchase fails.
    func purchase(options: Set<Product.PurchaseOption>) async throws -> Product.PurchaseResult
}

/// Extends StoreKit's Product to conform to SubscriptionProduct.
@available(macOS 12.0, iOS 15.0, *)
extension Product: SubscriptionProduct {
    /// Determines if this is a monthly subscription by checking if the subscription period
    /// is exactly one month.
    public var isMonthly: Bool {
        guard let subscription else { return false }
        return subscription.subscriptionPeriod.unit == .month &&
        subscription.subscriptionPeriod.value == 1
    }

    /// Determines if this is a yearly subscription by checking if the subscription period
    /// is exactly one year.
    public var isYearly: Bool {
        guard let subscription else { return false }
        return subscription.subscriptionPeriod.unit == .year &&
        subscription.subscriptionPeriod.value == 1
    }

    /// Returns the introductory offer for this subscription if available.
    public var introductoryOffer: (any SubscriptionProductIntroductoryOffer)? {
        subscription?.introductoryOffer
    }

    /// Indicates whether this subscription has a Free Trial offer.
    public var hasFreeTrialOffer: Bool {
        return subscription?.introductoryOffer?.isFreeTrial ?? false
    }

    /// Asynchronously checks if the user is eligible for an introductory offer.
    public var isEligibleForIntroOffer: Bool {
        get async {
            guard let subscription else { return false }
            return await subscription.isEligibleForIntroOffer
        }
    }

    /// Implements Equatable by comparing product IDs.
    public static func == (lhs: Product, rhs: Product) -> Bool {
        return lhs.id == rhs.id
    }
}

/// A protocol for types that can fetch subscription products.
@available(macOS 12.0, iOS 15.0, *)
public protocol ProductFetching {
    /// Fetches products for the specified identifiers.
    /// - Parameter identifiers: An array of product identifiers to fetch.
    /// - Returns: An array of subscription products.
    /// - Throws: An error if the fetch operation fails.
    func products(for identifiers: [String]) async throws -> [any SubscriptionProduct]
}

/// A default implementation of ProductFetching that uses StoreKit's standard product fetching.
@available(macOS 12.0, iOS 15.0, *)
public final class DefaultProductFetcher: ProductFetching {
    /// Initializes a new DefaultProductFetcher instance.
    public init() {}

    /// Fetches products using StoreKit's Product.products API.
    /// - Parameter identifiers: An array of product identifiers to fetch.
    /// - Returns: An array of subscription products.
    /// - Throws: An error if the fetch operation fails.
    public func products(for identifiers: [String]) async throws -> [any SubscriptionProduct] {
        return try await Product.products(for: identifiers)
    }
}

public protocol StorePurchaseManager {
    typealias TransactionJWS = String

    /// Returns the available subscription options that DON'T include Free Trial periods.
    /// - Returns: A `SubscriptionOptions` object containing the available subscription plans and pricing,
    ///           or `nil` if no options are available or cannot be fetched.
    func subscriptionOptions() async -> SubscriptionOptions?

    /// Returns the subscription options that include Free Trial periods.
    /// - Returns: A `SubscriptionOptions` object containing subscription plans with free trial offers,
    ///           or `nil` if no free trial options are available or the user is not eligible.
    func freeTrialSubscriptionOptions() async -> SubscriptionOptions?

    var purchasedProductIDs: [String] { get }
    var purchaseQueue: [String] { get }
    var areProductsAvailable: Bool { get }
    var currentStorefrontRegion: SubscriptionRegion { get }

    @MainActor func syncAppleIDAccount() async throws
    @MainActor func updateAvailableProducts() async
    @MainActor func updatePurchasedProducts() async
    @MainActor func mostRecentTransaction() async -> String?
    @MainActor func hasActiveSubscription() async -> Bool

    @MainActor func purchaseSubscription(with identifier: String, externalID: String) async -> Result<StorePurchaseManager.TransactionJWS, StorePurchaseManagerError>
}

@available(macOS 12.0, iOS 15.0, *) typealias Transaction = StoreKit.Transaction

@available(macOS 12.0, iOS 15.0, *)
public final class DefaultStorePurchaseManager: ObservableObject, StorePurchaseManager {

    private let storeSubscriptionConfiguration: StoreSubscriptionConfiguration
    private let subscriptionFeatureMappingCache: SubscriptionFeatureMappingCache
    private let subscriptionFeatureFlagger: FeatureFlaggerMapping<SubscriptionFeatureFlags>?

    @Published public private(set) var availableProducts: [any SubscriptionProduct] = []
    @Published public private(set) var purchasedProductIDs: [String] = []
    @Published public private(set) var purchaseQueue: [String] = []

    public var areProductsAvailable: Bool { !availableProducts.isEmpty }
    public private(set) var currentStorefrontRegion: SubscriptionRegion = .usa
    private var transactionUpdates: Task<Void, Never>?
    private var storefrontChanges: Task<Void, Never>?

    private var productFetcher: ProductFetching

    public init(subscriptionFeatureMappingCache: SubscriptionFeatureMappingCache,
                subscriptionFeatureFlagger: FeatureFlaggerMapping<SubscriptionFeatureFlags>? = nil,
                productFetcher: ProductFetching = DefaultProductFetcher()) {
        self.storeSubscriptionConfiguration = DefaultStoreSubscriptionConfiguration()
        self.subscriptionFeatureMappingCache = subscriptionFeatureMappingCache
        self.subscriptionFeatureFlagger = subscriptionFeatureFlagger
        self.productFetcher = productFetcher
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

            Logger.subscription.info("[StorePurchaseManager] Before AppStore.sync()")

            try await AppStore.sync()

            Logger.subscription.info("[StorePurchaseManager] After AppStore.sync()")

            await updatePurchasedProducts()
            await updateAvailableProducts()
        } catch {
            Logger.subscription.error("[StorePurchaseManager] Error: \(String(reflecting: error), privacy: .public) (\(error.localizedDescription, privacy: .public))")
            throw error
        }
    }

    public func subscriptionOptions() async -> SubscriptionOptions? {
        let nonFreeTrialProducts = availableProducts.filter { !$0.hasFreeTrialOffer }
        return await subscriptionOptions(for: nonFreeTrialProducts)
    }

    public func freeTrialSubscriptionOptions() async -> SubscriptionOptions? {
        let freeTrialProducts = availableProducts.filter { $0.hasFreeTrialOffer }
        return await subscriptionOptions(for: freeTrialProducts)
    }

    @MainActor
    public func updateAvailableProducts() async {
        Logger.subscription.info("[StorePurchaseManager] updateAvailableProducts")

        do {
            let storefrontCountryCode: String?
            let storefrontRegion: SubscriptionRegion

            if let featureFlagger = subscriptionFeatureFlagger, featureFlagger.isFeatureOn(.isLaunchedROW) || featureFlagger.isFeatureOn(.isLaunchedROWOverride) {
                if let subscriptionFeatureFlagger, subscriptionFeatureFlagger.isFeatureOn(.usePrivacyProUSARegionOverride) {
                    storefrontCountryCode = "USA"
                } else if let subscriptionFeatureFlagger, subscriptionFeatureFlagger.isFeatureOn(.usePrivacyProROWRegionOverride) {
                    storefrontCountryCode = "POL"
                } else {
                    storefrontCountryCode = await Storefront.current?.countryCode
                }

                storefrontRegion = SubscriptionRegion.matchingRegion(for: storefrontCountryCode ?? "USA") ?? .usa // Fallback to USA
            } else {
                storefrontCountryCode = "USA"
                storefrontRegion = .usa
            }

            self.currentStorefrontRegion = storefrontRegion
            let applicableProductIdentifiers = storeSubscriptionConfiguration.subscriptionIdentifiers(for: storefrontRegion)
            let availableProducts = try await productFetcher.products(for: applicableProductIdentifiers)
            Logger.subscription.info("[StorePurchaseManager] updateAvailableProducts fetched \(availableProducts.count) products for \(storefrontCountryCode ?? "<nil>", privacy: .public)")

            if Set(availableProducts.map { $0.id }) != Set(self.availableProducts.map { $0.id }) {
                self.availableProducts = availableProducts

                // Update cached subscription features mapping
                for id in availableProducts.compactMap({ $0.id }) {
                    _ = await subscriptionFeatureMappingCache.subscriptionFeatures(for: id)
                }
            }
        } catch {
            Logger.subscription.error("[StorePurchaseManager] Error: \(String(reflecting: error), privacy: .public)")
        }
    }
    

    @MainActor
    public func updatePurchasedProducts() async {
        Logger.subscription.info("[StorePurchaseManager] updatePurchasedProducts")

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
            Logger.subscription.error("[StorePurchaseManager] Error: \(String(reflecting: error), privacy: .public)")
        }

        Logger.subscription.info("[StorePurchaseManager] updatePurchasedProducts fetched \(purchasedSubscriptions.count) active subscriptions")

        if self.purchasedProductIDs != purchasedSubscriptions {
            self.purchasedProductIDs = purchasedSubscriptions
        }
    }

    @MainActor
    public func mostRecentTransaction() async -> String? {
        Logger.subscription.info("[StorePurchaseManager] mostRecentTransaction")

        var transactions: [VerificationResult<Transaction>] = []

        for await result in Transaction.all {
            transactions.append(result)
        }

        Logger.subscription.info("[StorePurchaseManager] mostRecentTransaction fetched \(transactions.count) transactions")

        return transactions.first?.jwsRepresentation
    }

    @MainActor
    public func hasActiveSubscription() async -> Bool {
        Logger.subscription.info("[StorePurchaseManager] hasActiveSubscription")

        var transactions: [VerificationResult<Transaction>] = []

        for await result in Transaction.currentEntitlements {
            transactions.append(result)
        }

        Logger.subscription.info("[StorePurchaseManager] hasActiveSubscription fetched \(transactions.count) transactions")

        return !transactions.isEmpty
    }

    @MainActor
    public func purchaseSubscription(with identifier: String, externalID: String) async -> Result<TransactionJWS, StorePurchaseManagerError> {

        guard let product = availableProducts.first(where: { $0.id == identifier }) else { return .failure(StorePurchaseManagerError.productNotFound) }

        Logger.subscription.info("[StorePurchaseManager] purchaseSubscription \(product.displayName, privacy: .public) (\(externalID, privacy: .public))")

        purchaseQueue.append(product.id)

        var options: Set<Product.PurchaseOption> = Set()

        if let token = UUID(uuidString: externalID) {
            options.insert(.appAccountToken(token))
        } else {
            Logger.subscription.error("[StorePurchaseManager] Error: Failed to create UUID")
            return .failure(StorePurchaseManagerError.externalIDisNotAValidUUID)
        }

        let purchaseResult: Product.PurchaseResult
        do {
            purchaseResult = try await product.purchase(options: options)
        } catch {
            Logger.subscription.error("[StorePurchaseManager] Error: \(String(reflecting: error), privacy: .public)")
            return .failure(StorePurchaseManagerError.purchaseFailed)
        }

        Logger.subscription.info("[StorePurchaseManager] purchaseSubscription complete")

        purchaseQueue.removeAll()

        switch purchaseResult {
        case let .success(verificationResult):
            switch verificationResult {
            case let .verified(transaction):
                Logger.subscription.info("[StorePurchaseManager] purchaseSubscription result: success")
                // Successful purchase
                await transaction.finish()
                await self.updatePurchasedProducts()
                return .success(verificationResult.jwsRepresentation)
            case let .unverified(_, error):
                Logger.subscription.info("[StorePurchaseManager] purchaseSubscription result: success /unverified/ - \(String(reflecting: error), privacy: .public)")
                // Successful purchase but transaction/receipt can't be verified
                // Could be a jailbroken phone
                return .failure(StorePurchaseManagerError.transactionCannotBeVerified)
            }
        case .pending:
            Logger.subscription.info("[StorePurchaseManager] purchaseSubscription result: pending")
            // Transaction waiting on SCA (Strong Customer Authentication) or
            // approval from Ask to Buy
            return .failure(StorePurchaseManagerError.transactionPendingAuthentication)
        case .userCancelled:
            Logger.subscription.info("[StorePurchaseManager] purchaseSubscription result: user cancelled")
            return .failure(StorePurchaseManagerError.purchaseCancelledByUser)
        @unknown default:
            Logger.subscription.info("[StorePurchaseManager] purchaseSubscription result: unknown")
            return .failure(StorePurchaseManagerError.unknownError)
        }
    }

    private func subscriptionOptions(for products: [any SubscriptionProduct]) async -> SubscriptionOptions? {
        Logger.subscription.info("[AppStorePurchaseFlow] subscriptionOptions")
        let monthly = products.first(where: { $0.isMonthly })
        let yearly = products.first(where: { $0.isYearly })
        guard let monthly, let yearly else {
            Logger.subscription.error("[AppStorePurchaseFlow] No products found")
            return nil
        }

        let platform: SubscriptionPlatformName = {
#if os(iOS)
           .ios
#else
           .macos
#endif
        }()

        let options: [SubscriptionOption] = await [.init(from: monthly, withRecurrence: "monthly"),
                       .init(from: yearly, withRecurrence: "yearly")]

        let features: [SubscriptionFeature]

        if let featureFlagger = subscriptionFeatureFlagger, featureFlagger.isFeatureOn(.isLaunchedROW) || featureFlagger.isFeatureOn(.isLaunchedROWOverride) {
            features = await subscriptionFeatureMappingCache.subscriptionFeatures(for: monthly.id).compactMap { SubscriptionFeature(name: $0) }
        } else {
            let allFeatures: [Entitlement.ProductName] = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration]
            features = allFeatures.compactMap { SubscriptionFeature(name: $0) }
        }

        return SubscriptionOptions(platform: platform,
                                   options: options,
                                   features: features)
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
                Logger.subscription.info("[StorePurchaseManager] observeTransactionUpdates")

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
                Logger.subscription.info("[StorePurchaseManager] observeStorefrontChanges: \(result.countryCode)")
                await self?.updatePurchasedProducts()
                await self?.updateAvailableProducts()
            }
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
private extension SubscriptionOption {

    init(from product: any SubscriptionProduct, withRecurrence recurrence: String) async {
        var offer: SubscriptionOptionOffer?

        if let introOffer = product.introductoryOffer, introOffer.isFreeTrial {

            let durationInDays = introOffer.periodInDays
            let isUserEligible = await product.isEligibleForIntroOffer

            offer = .init(type: .freeTrial, id: introOffer.id ?? "", displayPrice: introOffer.displayPrice, durationInDays: durationInDays, isUserEligible: isUserEligible)
        }

        self.init(id: product.id, cost: .init(displayPrice: product.displayPrice, recurrence: recurrence), offer: offer)
    }
}

@available(macOS 12.0, iOS 15.0, *)
private extension Product.SubscriptionPeriod {

    var periodInDays: Int {
        switch unit {
        case .day: return value
        case .week: return value * 7
        case .month: return value * 30
        case .year: return value * 365
        @unknown default:
            return value
        }
    }
}

public extension UserDefaults {

    enum Constants {
        static let storefrontRegionOverrideKey = "Subscription.debug.storefrontRegionOverride"
        static let usaValue = "usa"
        static let rowValue = "row"
    }

    dynamic var storefrontRegionOverride: SubscriptionRegion? {
        get {
            switch string(forKey: Constants.storefrontRegionOverrideKey) {
            case "usa":
                return .usa
            case "row":
                return .restOfWorld
            default:
                return nil
            }
        }

        set {
            switch newValue {
            case .usa:
                set(Constants.usaValue, forKey: Constants.storefrontRegionOverrideKey)
            case .restOfWorld:
                set(Constants.rowValue, forKey: Constants.storefrontRegionOverrideKey)
            default:
                removeObject(forKey: Constants.storefrontRegionOverrideKey)
            }
        }
    }
}
