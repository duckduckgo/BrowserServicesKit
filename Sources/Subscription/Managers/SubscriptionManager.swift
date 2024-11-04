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

enum SubscriptionManagerError: Error {
    case unsupportedSubscription
    case tokenUnavailable
    case confirmationHasInvalidSubscription
}

public protocol SubscriptionManager {

    // Environment
    static func loadEnvironmentFrom(userDefaults: UserDefaults) -> SubscriptionEnvironment?
    static func save(subscriptionEnvironment: SubscriptionEnvironment, userDefaults: UserDefaults)
    var currentEnvironment: SubscriptionEnvironment { get }

    /// Tries to get an authentication token and request the subscription
    func loadInitialData()

    // Subscription
    func refreshCachedSubscription(completion: @escaping (_ isSubscriptionActive: Bool) -> Void)
    func currentSubscription(refresh: Bool) async throws -> PrivacyProSubscription
    func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> PrivacyProSubscription
    var canPurchase: Bool { get }
    func clearSubscriptionCache()

    @available(macOS 12.0, iOS 15.0, *) func storePurchaseManager() -> StorePurchaseManager
    func url(for type: SubscriptionURL) -> URL

    func getCustomerPortalURL() async throws -> URL

    // User
    var isUserAuthenticated: Bool { get }
    var userEmail: String? { get }
    var entitlements: [SubscriptionEntitlement] { get }

    @discardableResult func getTokenContainer(policy: TokensCachePolicy) async throws -> TokenContainer
    func getTokenContainerSynchronously(policy: TokensCachePolicy) -> TokenContainer?
    func exchange(tokenV1: String) async throws -> TokenContainer

//    func signOut(skipNotification: Bool)
    func signOut() async

    func confirmPurchase(signature: String) async throws -> PrivacyProSubscription
}

/// Single entry point for everything related to Subscription. This manager is disposable, every time something related to the environment changes this need to be recreated.
public final class DefaultSubscriptionManager: SubscriptionManager {

    private let oAuthClient: any OAuthClient
    private let _storePurchaseManager: StorePurchaseManager?
    private let subscriptionEndpointService: SubscriptionEndpointService

    public let currentEnvironment: SubscriptionEnvironment
    public private(set) var canPurchase: Bool = false

    public init(storePurchaseManager: StorePurchaseManager? = nil,
                oAuthClient: any OAuthClient,
                subscriptionEndpointService: SubscriptionEndpointService,
                subscriptionEnvironment: SubscriptionEnvironment) {
        self._storePurchaseManager = storePurchaseManager
        self.oAuthClient = oAuthClient
        self.subscriptionEndpointService = subscriptionEndpointService
        self.currentEnvironment = subscriptionEnvironment
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

    // MARK: - Environment, ex SubscriptionPurchaseEnvironment

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

    public func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> PrivacyProSubscription {
        let tokenContainer = try await oAuthClient.activate(withPlatformSignature: lastTransactionJWSRepresentation)
        return try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)
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

    public var entitlements: [SubscriptionEntitlement] {
        return oAuthClient.currentTokenContainer?.decodedAccessToken.subscriptionEntitlements ?? []
    }

    private func refreshAccount() async {
        do {
            try await getTokenContainer(policy: .localForceRefresh)
            NotificationCenter.default.post(name: .entitlementsDidChange, object: self, userInfo: nil)
        } catch {
            Logger.subscription.error("Failed to refresh account: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult public func getTokenContainer(policy: TokensCachePolicy) async throws -> TokenContainer {
        do {
            return try await oAuthClient.getTokens(policy: policy)
        } catch OAuthClientError.deadToken {
            return try await throwAppropriateDeadTokenError()
        } catch {
            throw error
        }
    }

    /// If the client succeeds in making a refresh request but does not get the response, then the second refresh request will fail with `invalidTokenRequest` and the stored token will become unusable and un-refreshable.
    private func throwAppropriateDeadTokenError() async throws -> TokenContainer {
        Logger.subscription.log("Dead token detected")
        do {
            let subscription = try await subscriptionEndpointService.getSubscription(accessToken: "some", cachePolicy: .returnCacheDataDontLoad)
            switch subscription.platform {
            case .apple:
                Logger.subscription.log("Recovering Apple App Store subscription")
                // TODO: how do we handle this?
                throw OAuthClientError.deadToken
            case .stripe:
                Logger.subscription.error("Trying to recover a Stripe subscription is unsupported")
                throw SubscriptionManagerError.unsupportedSubscription
            default:
                throw SubscriptionManagerError.unsupportedSubscription
            }
        } catch {
            throw SubscriptionManagerError.tokenUnavailable
        }
    }

    public func getTokenContainerSynchronously(policy: TokensCachePolicy) -> TokenContainer? {
        Logger.subscription.debug("Fetching tokens synchronously")
        let semaphore = DispatchSemaphore(value: 0)
        var container: TokenContainer?
        Task {
            container = try await getTokenContainer(policy: policy)
            semaphore.signal()
        }
        semaphore.wait()
        return container
    }

    public func exchange(tokenV1: String) async throws -> TokenContainer {
        try await oAuthClient.exchange(accessTokenV1: tokenV1)
    }

//    public func signOut(skipNotification: Bool = false) {
//        Task {
//            await signOut()
//            if !skipNotification {
//                NotificationCenter.default.post(name: .accountDidSignOut, object: self, userInfo: nil)
//            }
//        }
//    }

    public func signOut() async {
        Logger.subscription.log("Removing all traces of the subscription and auth tokens")
        try? await oAuthClient.logout()
        subscriptionEndpointService.clearSubscription()
    }

    public func confirmPurchase(signature: String) async throws -> PrivacyProSubscription {
        let accessToken = try await getTokenContainer(policy: .localValid).accessToken
        let confirmation = try await subscriptionEndpointService.confirmPurchase(accessToken: accessToken, signature: signature)
        let subscription = confirmation.subscription
        subscriptionEndpointService.updateCache(with: subscription)
        return subscription
    }
}
