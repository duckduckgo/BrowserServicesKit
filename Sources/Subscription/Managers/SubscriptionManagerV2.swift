//
//  SubscriptionManagerV2.swift
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

public enum SubscriptionManagerError: Error, Equatable, LocalizedError {
    case tokenUnavailable(error: Error?)
    case confirmationHasInvalidSubscription
    case noProductsFound
    case tokenUnRefreshable

    public static func == (lhs: SubscriptionManagerError, rhs: SubscriptionManagerError) -> Bool {
        switch (lhs, rhs) {
        case (.tokenUnavailable(let lhsError), .tokenUnavailable(let rhsError)):
            return lhsError?.localizedDescription == rhsError?.localizedDescription
        case (.confirmationHasInvalidSubscription, .confirmationHasInvalidSubscription),
            (.noProductsFound, .noProductsFound),
            (.tokenUnRefreshable, .tokenUnRefreshable):
            return true
        default:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .tokenUnavailable(error: let error):
            "Token unavailable: \(String(describing: error))"
        case .confirmationHasInvalidSubscription:
            "Confirmation has an invalid subscription"
        case .noProductsFound:
            "No products found"
        case .tokenUnRefreshable:
            "Token is not refreshable, the account will be log out"
        }
    }
}

public enum SubscriptionPixelType {
    case deadToken
    case v1MigrationSuccessful
    case v1MigrationFailed
    case subscriptionIsActive
}

public protocol SubscriptionManagerV2: SubscriptionTokenProvider {

    // Environment
    static func loadEnvironmentFrom(userDefaults: UserDefaults) -> SubscriptionEnvironment?
    static func save(subscriptionEnvironment: SubscriptionEnvironment, userDefaults: UserDefaults)
    var currentEnvironment: SubscriptionEnvironment { get }

    /// Tries to get an authentication token and request the subscription
    func loadInitialData() async

    // Subscription
    @discardableResult func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription

    /// Tries to activate a subscription using a platform signature
    /// - Parameter lastTransactionJWSRepresentation: A platform signature coming from the AppStore
    /// - Returns: A subscription if found
    /// - Throws: An error if the access token is not available or something goes wrong in the api requests
    func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> PrivacyProSubscription?

    var canPurchase: Bool { get }
    func getProducts() async throws -> [GetProductsItem]

    @available(macOS 12.0, iOS 15.0, *) func storePurchaseManager() -> StorePurchaseManagerV2
    func url(for type: SubscriptionURL) -> URL

    func getCustomerPortalURL() async throws -> URL

    // User
    var isUserAuthenticated: Bool { get }
    var userEmail: String? { get }

    /// Sign out the user and clear all the tokens and subscription cache
    func signOut(notifyUI: Bool) async

    func clearSubscriptionCache()

    /// Confirm a purchase with a platform signature
    func confirmPurchase(signature: String, additionalParams: [String: String]?) async throws -> PrivacyProSubscription

    /// Pixels handler
    typealias PixelHandler = (SubscriptionPixelType) -> Void

    /// Closure called when an expired refresh token is detected and the Subscription login is invalid. An attempt to automatically recover it can be performed or the app can ask the user to do it manually
    typealias AutoRecoveryHandler = () async throws -> Void

    // MARK: - Features

    /// Get the current subscription features
    /// A feature is based on an entitlement and can be enabled or disabled
    /// A user cant have an entitlement without the feature, if a user is missing an entitlement the feature is disabled
    func currentSubscriptionFeatures(forceRefresh: Bool) async -> [SubscriptionFeatureV2]

    /// True if the feature can be used by the user, false otherwise
    func isFeatureAvailableForUser(_ entitlement: SubscriptionEntitlement) async -> Bool

    // MARK: - Token Management

    /// Get a token container accordingly to the policy
    /// - Parameter policy: The policy that will be used to get the token, it effects the tokens source and validity
    /// - Returns: The TokenContainer
    /// - Throws: A `SubscriptionManagerError`.
    ///     `tokenUnRefreshable` if the token is cannot be refreshed, typically due to an expired refresh token.
    ///     `tokenUnavailable` if the token is not available for the reason specified by the underlying error.
    @discardableResult
    func getTokenContainer(policy: AuthTokensCachePolicy) async throws -> TokenContainer

    /// Exchange access token v1 for a access token v2
    /// - Parameter tokenV1: The Auth v1 access token
    /// - Returns: An auth v2 TokenContainer
    func exchange(tokenV1: String) async throws -> TokenContainer

    /// Used only from the Mac Packet Tunnel Provider when a token is received during configuration
    func adopt(tokenContainer: TokenContainer)

    /// Remove the stored token container
    func removeTokenContainer()
}

/// Single entry point for everything related to Subscription. This manager is disposable, every time something related to the environment changes this need to be recreated.
public final class DefaultSubscriptionManagerV2: SubscriptionManagerV2 {

    var oAuthClient: any OAuthClient
    private let _storePurchaseManager: StorePurchaseManagerV2?
    private let subscriptionEndpointService: SubscriptionEndpointServiceV2
    private let pixelHandler: PixelHandler
    private let autoRecoveryHandler: AutoRecoveryHandler
    public let currentEnvironment: SubscriptionEnvironment

    public init(storePurchaseManager: StorePurchaseManagerV2? = nil,
                oAuthClient: any OAuthClient,
                subscriptionEndpointService: SubscriptionEndpointServiceV2,
                subscriptionEnvironment: SubscriptionEnvironment,
                pixelHandler: @escaping PixelHandler,
                autoRecoveryHandler: @escaping AutoRecoveryHandler) {
        self._storePurchaseManager = storePurchaseManager
        self.oAuthClient = oAuthClient
        self.subscriptionEndpointService = subscriptionEndpointService
        self.currentEnvironment = subscriptionEnvironment
        self.pixelHandler = pixelHandler
        self.autoRecoveryHandler = autoRecoveryHandler

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
        return storePurchaseManager.areProductsAvailable
    }

    @available(macOS 12.0, iOS 15.0, *)
    public func storePurchaseManager() -> StorePurchaseManagerV2 {
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

    public func loadInitialData() async {

        // Attempting V1 token migration
        // IMPORTANT: This MUST be the first operation executed by Subscription
        do {
            if (try await oAuthClient.migrateV1Token()) != nil {
                pixelHandler(.v1MigrationSuccessful)

                // cleaning up old data
                clearSubscriptionCache()
            }
        } catch {
            Logger.subscription.error("Failed to migrate V1 token: \(error, privacy: .public)")
            pixelHandler(.v1MigrationFailed)
        }

        // Fetching fresh subscription
        if isUserAuthenticated {
            do {
                let subscription = try await getSubscription(cachePolicy: .reloadIgnoringLocalCacheData)
                Logger.subscription.log("Subscription is \(subscription.isActive ? "active" : "not active", privacy: .public)")
                if subscription.isActive {
                    pixelHandler(.subscriptionIsActive)
                }
            } catch {
                Logger.subscription.error("Failed to load initial subscription data: \(error, privacy: .public)")
            }
        }
    }

    @discardableResult
    public func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription {
        guard isUserAuthenticated else {
            throw SubscriptionEndpointServiceError.noData
        }

        do {
            let tokenContainer = try await getTokenContainer(policy: .localValid)
            return try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken, cachePolicy: cachePolicy)
        } catch SubscriptionEndpointServiceError.noData {
            throw SubscriptionEndpointServiceError.noData
        } catch {
            Logger.networking.error("Error getting subscription: \(error, privacy: .public)")
            throw SubscriptionEndpointServiceError.noData
        }
    }

    public func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> PrivacyProSubscription? {
        do {
            let tokenContainer = try await oAuthClient.activate(withPlatformSignature: lastTransactionJWSRepresentation)
            return try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)
        } catch SubscriptionEndpointServiceError.noData {
            return nil
        } catch {
            throw error
        }
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
        guard isUserAuthenticated else {
            throw SubscriptionEndpointServiceError.noData
        }

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

    @discardableResult public func getTokenContainer(policy: AuthTokensCachePolicy) async throws -> TokenContainer {
        Logger.subscription.debug("Get tokens \(policy.description, privacy: .public)")
        do {
            let referenceCachedTokenContainer = try? await oAuthClient.getTokens(policy: .local)
            let referenceCachedEntitlements = referenceCachedTokenContainer?.decodedAccessToken.subscriptionEntitlements
            let resultTokenContainer = try await oAuthClient.getTokens(policy: policy)
            let newEntitlements = resultTokenContainer.decodedAccessToken.subscriptionEntitlements

            // Send notification when entitlements change
            if referenceCachedEntitlements != newEntitlements {
                Logger.subscription.debug("Entitlements changed - New \(newEntitlements) Old \(String(describing: referenceCachedEntitlements))")
                NotificationCenter.default.post(name: .entitlementsDidChange, object: self, userInfo: [UserDefaultsCacheKey.subscriptionEntitlements: newEntitlements])
            }

            // Send "accountDidSignIn" notification when login changes
            if referenceCachedTokenContainer == nil {
                Logger.subscription.debug("New login detected")
                NotificationCenter.default.post(name: .accountDidSignIn, object: self, userInfo: nil)
            }
            return resultTokenContainer
        } catch OAuthClientError.refreshTokenExpired {
            do { return try await attemptTokenRecovery() } catch { throw error }
        } catch {
            throw SubscriptionManagerError.tokenUnavailable(error: error)
        }
    }

    func attemptTokenRecovery() async throws -> TokenContainer {
        Logger.subscription.log("The refresh token is expired, attempting subscription recovery...")
        await signOut(notifyUI: false)
        do {
            try await autoRecoveryHandler()
            return try await getTokenContainer(policy: .local)
        } catch {
            throw SubscriptionManagerError.tokenUnRefreshable
        }
    }

    public func exchange(tokenV1: String) async throws -> TokenContainer {
        let tokenContainer = try await oAuthClient.exchange(accessTokenV1: tokenV1)
        NotificationCenter.default.post(name: .accountDidSignIn, object: self, userInfo: nil)
        return tokenContainer
    }

    public func adopt(tokenContainer: TokenContainer) {
        oAuthClient.adopt(tokenContainer: tokenContainer)
    }

    public func removeTokenContainer() {
        oAuthClient.removeLocalAccount()
    }

    public func signOut(notifyUI: Bool) async {
        Logger.subscription.log("SignOut: Removing all traces of the subscription and auth tokens")
        try? await oAuthClient.logout()
        clearSubscriptionCache()
        if notifyUI {
            Logger.subscription.debug("SignOut: Notifying the UI")
            NotificationCenter.default.post(name: .accountDidSignOut, object: self, userInfo: nil)
        }
    }

    public func confirmPurchase(signature: String, additionalParams: [String: String]?) async throws -> PrivacyProSubscription {
        Logger.subscription.log("Confirming Purchase...")
        let accessToken = try await getTokenContainer(policy: .localValid).accessToken
        let confirmation = try await subscriptionEndpointService.confirmPurchase(accessToken: accessToken,
                                                                                 signature: signature,
                                                                                 additionalParams: additionalParams)
        try await subscriptionEndpointService.ingestSubscription(confirmation.subscription)
        Logger.subscription.log("Purchase confirmed!")
        return confirmation.subscription
    }

    // MARK: - Features

    /// Returns the features available for the current subscription, a feature is enabled only if the user has the corresponding entitlement
    /// - Parameter forceRefresh: ignore subscription and token cache and re-download everything
    /// - Returns: An Array of SubscriptionFeature where each feature is enabled or disabled based on the user entitlements
    public func currentSubscriptionFeatures(forceRefresh: Bool) async -> [SubscriptionFeatureV2] {
        guard isUserAuthenticated else { return [] }

        do {
            let tokenContainer = try await getTokenContainer(policy: forceRefresh ? .localForceRefresh : .localValid)
            let currentSubscription = try await getSubscription(cachePolicy: forceRefresh ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad)

            let userEntitlements = tokenContainer.decodedAccessToken.subscriptionEntitlements // What the user has access to
            let availableFeatures = currentSubscription.features ?? [] // what the subscription is capable to provide

            // Filter out the features that are not available because the user doesn't have the right entitlements
            let result = availableFeatures.map({ featureEntitlement in
                let enabled = userEntitlements.contains(featureEntitlement)
                return SubscriptionFeatureV2(entitlement: featureEntitlement, isAvailableForUser: enabled)
            })
            Logger.subscription.log("""
User entitlements: \(userEntitlements, privacy: .public)
Available Features: \(availableFeatures, privacy: .public)
Subscription features: \(result, privacy: .public)
""")
            return result
        } catch {
            Logger.subscription.error("Error retrieving subscription features: \(error, privacy: .public)")
            return []
        }
    }

    public func isFeatureAvailableForUser(_ entitlement: SubscriptionEntitlement) async -> Bool {
        guard isUserAuthenticated else { return false }

        let currentFeatures = await currentSubscriptionFeatures(forceRefresh: false)
        return currentFeatures.contains { feature in
            feature.entitlement == entitlement && feature.isAvailableForUser
        }
    }
}

extension DefaultSubscriptionManagerV2: SubscriptionTokenProvider {
    public func getAccessToken() async throws -> String {
        try await getTokenContainer(policy: .localValid).accessToken
    }

    public func removeAccessToken() {
        removeTokenContainer()
    }
}
