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

    public static func == (lhs: SubscriptionManagerError, rhs: SubscriptionManagerError) -> Bool {
        switch (lhs, rhs) {
        case (.tokenUnavailable(let lhsError), .tokenUnavailable(let rhsError)):
            return lhsError?.localizedDescription == rhsError?.localizedDescription
        case (.confirmationHasInvalidSubscription, .confirmationHasInvalidSubscription):
            return true
        default:
            return false
        }
    }
}

public enum SubscriptionPixelType {
    case deadToken
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

/// Provider of the Subscription entitlements
public protocol SubscriptionEntitlementsProvider {

    func getEntitlements(forceRefresh: Bool) async throws -> [SubscriptionEntitlement]

    /// Get the cached subscription entitlements
    var currentEntitlements: [SubscriptionEntitlement] { get }

    /// Get the cached entitlements and check if a specific one is present
    func isEntitlementActive(_ entitlement: SubscriptionEntitlement) -> Bool
}

public protocol SubscriptionManager: SubscriptionTokenProvider, SubscriptionEntitlementsProvider {

    // Environment
    static func loadEnvironmentFrom(userDefaults: UserDefaults) -> SubscriptionEnvironment?
    static func save(subscriptionEnvironment: SubscriptionEnvironment, userDefaults: UserDefaults)
    var currentEnvironment: SubscriptionEnvironment { get }

    /// Tries to get an authentication token and request the subscription
    func loadInitialData()

    // Subscription
    func refreshCachedSubscription(completion: @escaping (_ isSubscriptionActive: Bool) -> Void)
    func currentSubscription(refresh: Bool) async throws -> PrivacyProSubscription
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
    func signOut(skipNotification: Bool) async

    func clearSubscriptionCache()

    /// Confirm a purchase with a platform signature
    func confirmPurchase(signature: String) async throws -> PrivacyProSubscription

    // Pixels
    typealias PixelHandler = (SubscriptionPixelType) -> Void
}

/// Single entry point for everything related to Subscription. This manager is disposable, every time something related to the environment changes this need to be recreated.
public final class DefaultSubscriptionManager: SubscriptionManager {

    var oAuthClient: any OAuthClient
    private let _storePurchaseManager: StorePurchaseManager?
    private let subscriptionEndpointService: SubscriptionEndpointService
    private let pixelHandler: PixelHandler
    public let currentEnvironment: SubscriptionEnvironment
    public private(set) var canPurchase: Bool = false

    public init(storePurchaseManager: StorePurchaseManager? = nil,
                oAuthClient: any OAuthClient,
                subscriptionEndpointService: SubscriptionEndpointService,
                subscriptionEnvironment: SubscriptionEnvironment,
                pixelHandler: @escaping PixelHandler) {
        self._storePurchaseManager = storePurchaseManager
        self.oAuthClient = oAuthClient
        self.subscriptionEndpointService = subscriptionEndpointService
        self.currentEnvironment = subscriptionEnvironment
        self.pixelHandler = pixelHandler

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
            canPurchase = storePurchaseManager().areProductsAvailable
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

    public func currentSubscription(refresh: Bool) async throws -> PrivacyProSubscription {
        let tokenContainer = try await getTokenContainer(policy: .localValid)
        do {
            return try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken, cachePolicy: refresh ? .reloadIgnoringLocalCacheData : .returnCacheDataDontLoad )
        } catch SubscriptionEndpointServiceError.noData {
            await signOut()
            throw SubscriptionEndpointServiceError.noData
        }
    }

    public func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription {
        let tokenContainer = try await getTokenContainer(policy: .localValid)
        do {
            return try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken, cachePolicy: cachePolicy)
        } catch SubscriptionEndpointServiceError.noData {
            await signOut()
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

    public func getEntitlements(forceRefresh: Bool) async throws -> [SubscriptionEntitlement] {
        let tokenContainer = try await getTokenContainer(policy: forceRefresh ? .localForceRefresh : .localValid)
        return tokenContainer.decodedAccessToken.subscriptionEntitlements
    }

    public var currentEntitlements: [SubscriptionEntitlement] {
        return oAuthClient.currentTokenContainer?.decodedAccessToken.subscriptionEntitlements ?? []
    }

    public func isEntitlementActive(_ entitlement: SubscriptionEntitlement) -> Bool {
        currentEntitlements.contains(entitlement)
    }

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
            let referenceCachedEntitlements = referenceCachedTokenContainer?.decodedAccessToken.subscriptionEntitlements
            let resultTokenContainer = try await oAuthClient.getTokens(policy: policy)
            let newEntitlements = resultTokenContainer.decodedAccessToken.subscriptionEntitlements

            // Send notification when entitlements change
            if referenceCachedEntitlements != newEntitlements {
                NotificationCenter.default.post(name: .entitlementsDidChange, object: self, userInfo: [UserDefaultsCacheKey.subscriptionEntitlements: newEntitlements])
            }

            if referenceCachedTokenContainer == nil { // new login
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
        NotificationCenter.default.post(name: .accountDidSignIn, object: self, userInfo: nil) // move all the notifications down to the storage?
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

    public func signOut(skipNotification: Bool) async {
        await signOut()
        if !skipNotification {
            NotificationCenter.default.post(name: .accountDidSignOut, object: self, userInfo: nil)
        }
    }

    public func confirmPurchase(signature: String) async throws -> PrivacyProSubscription {
        let accessToken = try await getTokenContainer(policy: .localValid).accessToken
        let confirmation = try await subscriptionEndpointService.confirmPurchase(accessToken: accessToken, signature: signature)
        subscriptionEndpointService.updateCache(with: confirmation.subscription)
        return confirmation.subscription
    }
}
