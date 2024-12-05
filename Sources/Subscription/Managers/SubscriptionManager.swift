//
//  SubscriptionManager.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Common
import os.log
import Networking

public enum SubscriptionManagerError: Error, Equatable {
    case tokenUnavailable(error: Error?)
    case confirmationHasInvalidSubscription
    case noProductsFound

    public static func == (lhs: SubscriptionManagerError, rhs: SubscriptionManagerError) -> Bool {
        switch (lhs, rhs) {
        case (.tokenUnavailable(let lhsError), .tokenUnavailable(let rhsError)):
            return lhsError?.localizedDescription == rhsError?.localizedDescription
        case (.confirmationHasInvalidSubscription, .confirmationHasInvalidSubscription),
            (.noProductsFound, .noProductsFound):
            return true
        default:
            return false
        }
    }
}

public enum SubscriptionPixelType {
    case deadToken
}

/// A `SubscriptionFeature` is **available** if the specific feature is `on` for the specific subscription. Feature availability if decided based on the country and the local and remote feature flags.
/// A `SubscriptionFeature` is **enabled** if the logged in user has the required entitlements.
public struct SubscriptionFeature: Equatable, CustomDebugStringConvertible {
    public var entitlement: SubscriptionEntitlement
    public var enabled: Bool

    public var debugDescription: String {
        "\(entitlement.rawValue) is \(enabled ? "enabled" : "disabled")"
    }
}

/// The sole entity responsible of obtaining, storing and refreshing an OAuth Token
public protocol SubscriptionTokenProvider {

    /// Get a token container accordingly to the policy
    /// - Parameter policy: The policy that will be used to get the token, it effects the tokens source and validity
    /// - Returns: The TokenContainer
    /// - Throws: OAuthClientError.deadToken if the token is unrecoverable. SubscriptionEndpointServiceError.noData if the token is not available.
    @discardableResult
    func getTokenContainer(policy: TokensCachePolicy) async throws -> TokenContainer

    /// Get a token container synchronously accordingly to the policy
    /// - Parameter policy: The policy that will be used to get the token, it effects the tokens source and validity
    /// - Returns: The TokenContainer, nil in case of error
    func getTokenContainerSynchronously(policy: TokensCachePolicy) -> TokenContainer?

    /// Exchange access token v1 for a access token v2
    /// - Parameter tokenV1: The Auth v1 access token
    /// - Returns: An auth v2 TokenContainer
    func exchange(tokenV1: String) async throws -> TokenContainer

    /// Used only from the Mac Packet Tunnel Provider when a token is received during configuration
    func adopt(tokenContainer: TokenContainer) async throws

    /// Remove the stored token container
    func removeTokenContainer()
}

public protocol SubscriptionManager: SubscriptionTokenProvider {

//    var subscriptionFeatureMappingCache: SubscriptionFeatureMappingCache { get }

    // Environment
    static func loadEnvironmentFrom(userDefaults: UserDefaults) -> SubscriptionEnvironment?
    static func save(subscriptionEnvironment: SubscriptionEnvironment, userDefaults: UserDefaults)
    var currentEnvironment: SubscriptionEnvironment { get }

    /// Tries to get an authentication token and request the subscription
    func loadInitialData()

    // Subscription
    func refreshCachedSubscription(completion: @escaping (_ isSubscriptionActive: Bool) -> Void)
//    func currentSubscription(refresh: Bool) async throws -> PrivacyProSubscription
    func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription
    func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> PrivacyProSubscription
    var canPurchase: Bool { get }
    func getProducts() async throws -> [GetProductsItem]

    @available(macOS 12.0, iOS 15.0, *) func storePurchaseManager() -> StorePurchaseManager
    func url(for type: SubscriptionURL) -> URL

    func getCustomerPortalURL() async throws -> URL

    // User
    var isUserAuthenticated: Bool { get }
    var userEmail: String? { get }

    /// Sign out the user and clear all the tokens and subscription cache
    func signOut() async
//    func signOut(skipNotification: Bool) async

    func clearSubscriptionCache()

    /// Confirm a purchase with a platform signature
    func confirmPurchase(signature: String) async throws -> PrivacyProSubscription

    /// Pixels handler
    typealias PixelHandler = (SubscriptionPixelType) -> Void

//    func subscriptionOptions(platform: PrivacyProSubscription.Platform) async throws -> SubscriptionOptions

    // MARK: - Features

    /// Get the current subscription features
    /// A feature is based on an entitlement and can be enabled or disabled
    /// A user cant have an entitlement without the feature, if a user is missing an entitlement the feature is disabled
    func currentSubscriptionFeatures(forceRefresh: Bool) async -> [SubscriptionFeature]

    /// True if the feature can be used, false otherwise
    func isFeatureActive(_ entitlement: SubscriptionEntitlement) async -> Bool

//    var currentUserEntitlements: [SubscriptionEntitlement] { get }

//    func getEntitlements(forceRefresh: Bool) async throws -> [SubscriptionEntitlement]
//    /// Get the cached subscription entitlements
//    var currentEntitlements: [SubscriptionEntitlement] { get }
    /// Get the cached entitlements and check if a specific one is present
//    func isEntitlementActive(_ entitlement: SubscriptionEntitlement) -> Bool
}

/// Single entry point for everything related to Subscription. This manager is disposable, every time something related to the environment changes this need to be recreated.
public final class DefaultSubscriptionManager: SubscriptionManager {

    var oAuthClient: any OAuthClient
    private let _storePurchaseManager: StorePurchaseManager?
    private let subscriptionEndpointService: SubscriptionEndpointService
    private let pixelHandler: PixelHandler
    public let subscriptionFeatureMappingCache: SubscriptionFeatureMappingCache
    public let currentEnvironment: SubscriptionEnvironment

    private let subscriptionFeatureFlagger: FeatureFlaggerMapping<SubscriptionFeatureFlags>?

    public init(storePurchaseManager: StorePurchaseManager? = nil,
                oAuthClient: any OAuthClient,
                subscriptionEndpointService: SubscriptionEndpointService,
                subscriptionFeatureMappingCache: SubscriptionFeatureMappingCache,
                subscriptionEnvironment: SubscriptionEnvironment,
                subscriptionFeatureFlagger: FeatureFlaggerMapping<SubscriptionFeatureFlags>?,
                pixelHandler: @escaping PixelHandler) {
        self._storePurchaseManager = storePurchaseManager
        self.oAuthClient = oAuthClient
        self.subscriptionEndpointService = subscriptionEndpointService
        self.currentEnvironment = subscriptionEnvironment
        self.pixelHandler = pixelHandler
        self.subscriptionFeatureMappingCache = subscriptionFeatureMappingCache
        self.subscriptionFeatureFlagger = subscriptionFeatureFlagger

#if !NETP_SYSTEM_EXTENSION
        switch currentEnvironment.purchasePlatform {
        case .appStore:
            if #available(macOS 12.0, iOS 15.0, *) {
                setupForAppStore()
            } else {
                assertionFailure("Trying to setup AppStore where not supported")
            }
        case .stripe:
            break
        }
#endif
    }

    public var canPurchase: Bool {
        guard let storePurchaseManager = _storePurchaseManager else { return false }

        switch storePurchaseManager.currentStorefrontRegion {
        case .usa:
            return storePurchaseManager.areProductsAvailable
        case .restOfWorld:
            if let subscriptionFeatureFlagger,
               subscriptionFeatureFlagger.isFeatureOn(.isLaunchedROW) || subscriptionFeatureFlagger.isFeatureOn(.isLaunchedROWOverride) {
                return storePurchaseManager.areProductsAvailable
            } else {
                return false
            }
        }
    }

    @available(macOS 12.0, iOS 15.0, *)
    public func storePurchaseManager() -> StorePurchaseManager {
        return _storePurchaseManager!
    }

    // MARK: Load and Save SubscriptionEnvironment

    static private let subscriptionEnvironmentStorageKey = "com.duckduckgo.subscription.environment"
    static public func loadEnvironmentFrom(userDefaults: UserDefaults) -> SubscriptionEnvironment? {
        if let savedData = userDefaults.object(forKey: Self.subscriptionEnvironmentStorageKey) as? Data {
            let decoder = JSONDecoder()
            if let loadedData = try? decoder.decode(SubscriptionEnvironment.self, from: savedData) {
                return loadedData
            }
        }
        return nil
    }

    static public func save(subscriptionEnvironment: SubscriptionEnvironment, userDefaults: UserDefaults) {
        let encoder = JSONEncoder()
        if let encodedData = try? encoder.encode(subscriptionEnvironment) {
            userDefaults.set(encodedData, forKey: Self.subscriptionEnvironmentStorageKey)
        }
    }

    // MARK: - Environment

    @available(macOS 12.0, iOS 15.0, *) private func setupForAppStore() {
        Task {
            await storePurchaseManager().updateAvailableProducts()
        }
    }

    // MARK: - Subscription

    public func loadInitialData() {
        refreshCachedSubscription { isSubscriptionActive in
            Logger.subscription.log("Subscription is \(isSubscriptionActive ? "active" : "not active")")
        }
    }

    public func refreshCachedSubscription(completion: @escaping (_ isSubscriptionActive: Bool) -> Void) {
        Task {
            guard let tokenContainer = try? await getTokenContainer(policy: .localValid) else {
                completion(false)
                return
            }
            // Refetch and cache subscription
            let subscription = try? await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)
            completion(subscription?.isActive ?? false)
        }
    }

//    public func currentSubscription(refresh: Bool) async throws -> PrivacyProSubscription {
//        let tokenContainer = try await getTokenContainer(policy: .localValid)
//        do {
//            return try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken, cachePolicy: refresh ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad )
//        } catch SubscriptionEndpointServiceError.noData {
////            await signOut()
//            throw SubscriptionEndpointServiceError.noData
//        }
//    }

    public func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription {
        if !isUserAuthenticated {
            throw SubscriptionEndpointServiceError.noData
        }

        do {
            let tokenContainer = try await getTokenContainer(policy: .localValid)
            return try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken, cachePolicy: cachePolicy)
        } catch SubscriptionEndpointServiceError.noData {
//            await signOut()
            throw SubscriptionEndpointServiceError.noData
        }
    }

    public func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> PrivacyProSubscription {
        let tokenContainer = try await oAuthClient.activate(withPlatformSignature: lastTransactionJWSRepresentation)
        return try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)
    }

    public func getProducts() async throws -> [GetProductsItem] {
        try await subscriptionEndpointService.getProducts()
    }

    public func clearSubscriptionCache() {
        subscriptionEndpointService.clearSubscription()
    }

    // MARK: - URLs

    public func url(for type: SubscriptionURL) -> URL {
        type.subscriptionURL(environment: currentEnvironment.serviceEnvironment)
    }

    public func getCustomerPortalURL() async throws -> URL {
        let tokenContainer = try await getTokenContainer(policy: .localValid)
        // Get Stripe Customer Portal URL and update the model
        let serviceResponse = try await subscriptionEndpointService.getCustomerPortalURL(accessToken: tokenContainer.accessToken, externalID: tokenContainer.decodedAccessToken.externalID)
        guard let url = URL(string: serviceResponse.customerPortalUrl) else {
            throw SubscriptionEndpointServiceError.noData
        }
        return url
    }

    // MARK: - User
    public var isUserAuthenticated: Bool {
        oAuthClient.isUserAuthenticated
    }

    public var userEmail: String? {
        return oAuthClient.currentTokenContainer?.decodedAccessToken.email
    }

    // MARK: -

    private func refreshAccount() async {
        do {
            try await getTokenContainer(policy: .localForceRefresh)
        } catch {
            Logger.subscription.error("Failed to refresh account: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult public func getTokenContainer(policy: TokensCachePolicy) async throws -> TokenContainer {
        do {
            Logger.subscription.debug("Get tokens \(policy.description, privacy: .public)")

            let referenceCachedTokenContainer = try? await oAuthClient.getTokens(policy: .local)

            if policy == .local {
                if let localToken = referenceCachedTokenContainer {
                    return localToken
                } else {
                    throw SubscriptionManagerError.tokenUnavailable(error: nil)
                }
            }

            let referenceCachedEntitlements = referenceCachedTokenContainer?.decodedAccessToken.subscriptionEntitlements
            let resultTokenContainer = try await oAuthClient.getTokens(policy: policy)
            let newEntitlements = resultTokenContainer.decodedAccessToken.subscriptionEntitlements

            // Send notification when entitlements change
            if referenceCachedEntitlements != newEntitlements {
                Logger.subscription.debug("Entitlements changed: \(newEntitlements)")
                NotificationCenter.default.post(name: .entitlementsDidChange, object: self, userInfo: [UserDefaultsCacheKey.subscriptionEntitlements: newEntitlements])
            }

            if referenceCachedTokenContainer == nil { // new login
                Logger.subscription.debug("New login detected")
                NotificationCenter.default.post(name: .accountDidSignIn, object: self, userInfo: nil)
            }
            return resultTokenContainer
        } catch OAuthClientError.deadToken {
            return try await throwAppropriateDeadTokenError()
        } catch {
            throw SubscriptionManagerError.tokenUnavailable(error: error)
        }
    }

    /// If the client succeeds in making a refresh request but does not get the response, then the second refresh request will fail with `invalidTokenRequest` and the stored token will become unusable and un-refreshable.
    private func throwAppropriateDeadTokenError() async throws -> TokenContainer {
        Logger.subscription.warning("Dead token detected")
        do {
            let subscription = try await subscriptionEndpointService.getSubscription(accessToken: "", // Token is unused
                                                                                     cachePolicy: .returnCacheDataDontLoad)
            switch subscription.platform {
            case .apple:
                pixelHandler(.deadToken)
                throw OAuthClientError.deadToken
            default:
                throw SubscriptionManagerError.tokenUnavailable(error: nil)
            }
        } catch {
            throw SubscriptionManagerError.tokenUnavailable(error: error)
        }
    }

    public func getTokenContainerSynchronously(policy: TokensCachePolicy) -> TokenContainer? {
        Logger.subscription.debug("Fetching tokens synchronously")
        let semaphore = DispatchSemaphore(value: 0)

        Task(priority: .high) {
            defer { semaphore.signal() }
            return try? await getTokenContainer(policy: policy)
        }

        semaphore.wait()
        return nil
    }

    public func exchange(tokenV1: String) async throws -> TokenContainer {
        let tokenContainer = try await oAuthClient.exchange(accessTokenV1: tokenV1)
        NotificationCenter.default.post(name: .accountDidSignIn, object: self, userInfo: nil)
        return tokenContainer
    }

    public func adopt(tokenContainer: TokenContainer) async throws {
        oAuthClient.currentTokenContainer = tokenContainer
    }

    public func removeTokenContainer() {
        oAuthClient.removeLocalAccount()
    }

    public func signOut() async {
        Logger.subscription.log("Removing all traces of the subscription and auth tokens")
        try? await oAuthClient.logout()
        subscriptionEndpointService.clearSubscription()
        NotificationCenter.default.post(name: .accountDidSignOut, object: self, userInfo: nil)
    }

    public func confirmPurchase(signature: String) async throws -> PrivacyProSubscription {
        Logger.subscription.log("Confirming Purchase...")
        let accessToken = try await getTokenContainer(policy: .localValid).accessToken
        let confirmation = try await subscriptionEndpointService.confirmPurchase(accessToken: accessToken, signature: signature)
        subscriptionEndpointService.updateCache(with: confirmation.subscription)

        // refresh the tokens for fetching the new user entitlements
        await refreshAccount()

        Logger.subscription.log("Purchase confirmed!")
        return confirmation.subscription
    }

    // MARK: - Features

    public func currentSubscriptionFeatures(forceRefresh: Bool) async -> [SubscriptionFeature] {
        guard isUserAuthenticated else { return [] }

        if let subscriptionFeatureFlagger,
           subscriptionFeatureFlagger.isFeatureOn(.isLaunchedROW) || subscriptionFeatureFlagger.isFeatureOn(.isLaunchedROWOverride) {
            do {
                let subscription = try await getSubscription(cachePolicy: forceRefresh ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad)
                let tokenContainer = try await getTokenContainer(policy: forceRefresh ? .localForceRefresh : .local)
                let userEntitlements = tokenContainer.decodedAccessToken.subscriptionEntitlements
                let availableFeatures = await subscriptionFeatureMappingCache.subscriptionFeatures(for: subscription.productId)

                // Filter out the features that are not available because the user doesn't have the right entitlements
                let result = availableFeatures.map({ featureEntitlement in
                    let enabled = userEntitlements.contains(featureEntitlement)
                    return SubscriptionFeature(entitlement: featureEntitlement, enabled: enabled)
                })
                Logger.subscription.log("""
User entitlements: \(userEntitlements)
Available Features: \(availableFeatures)
Subscription features: \(result)
""")
                return result
            } catch {
                return []
            }
        } else {
            let result = [SubscriptionFeature(entitlement: .networkProtection, enabled: true),
                          SubscriptionFeature(entitlement: .dataBrokerProtection, enabled: true),
                          SubscriptionFeature(entitlement: .identityTheftRestoration, enabled: true)]
            Logger.subscription.debug("Default Subscription features: \(result)")
            return result
        }
    }

    public func isFeatureActive(_ entitlement: SubscriptionEntitlement) async -> Bool {
        let currentFeatures = await currentSubscriptionFeatures(forceRefresh: false)
        return currentFeatures.contains { feature in
            feature.entitlement == entitlement && feature.enabled
        }
    }

//    private var currentUserEntitlements: [SubscriptionEntitlement] {
//        return oAuthClient.currentTokenContainer?.decodedAccessToken.subscriptionEntitlements ?? []
//    }

    //    public func getEntitlements(forceRefresh: Bool) async throws -> [SubscriptionEntitlement] {
    //        if forceRefresh {
    //            await refreshAccount()
    //        }
    //        return currentEntitlements
    //    }
    //
    //
    //    public func isEntitlementActive(_ entitlement: SubscriptionEntitlement) -> Bool {
    //        currentEntitlements.contains(entitlement)
    //    }
    //    public func subscriptionOptions(platform: PrivacyProSubscription.Platform) async throws -> SubscriptionOptions {
    //        Logger.subscription.log("Getting subscription options for \(platform.rawValue, privacy: .public)")
    //
    //        switch platform {
    //        case .apple:
    //            break
    //        case .stripe:
    //            let products = try await getProducts()
    //            guard !products.isEmpty else {
    //                Logger.subscription.error("Failed to obtain products")
    //                throw SubscriptionManagerError.noProductsFound
    //            }
    //
    //            let currency = products.first?.currency ?? "USD"
    //
    //            let formatter = NumberFormatter()
    //            formatter.numberStyle = .currency
    //            formatter.locale = Locale(identifier: "en_US@currency=\(currency)")
    //
    //            let options: [SubscriptionOption] = products.map {
    //                var displayPrice = "\($0.price) \($0.currency)"
    //
    //                if let price = Float($0.price), let formattedPrice = formatter.string(from: price as NSNumber) {
    //                     displayPrice = formattedPrice
    //                }
    //                let cost = SubscriptionOptionCost(displayPrice: displayPrice, recurrence: $0.billingPeriod.lowercased())
    //                return SubscriptionOption(id: $0.productId, cost: cost)
    //            }
    //
    //            let features: [SubscriptionEntitlement] = [.networkProtection,
    //                                                       .dataBrokerProtection,
    //                                                       .identityTheftRestoration]
    //            return SubscriptionOptions(platform: SubscriptionPlatformName.stripe,
    //                                       options: options,
    //                                       features: features)
    //        default:
    //            Logger.subscription.fault("Unsupported subscription platform: \(platform.rawValue, privacy: .public)")
    //            assertionFailure("Unsupported subscription platform: \(platform.rawValue)")
    //        }
    //    }
}
