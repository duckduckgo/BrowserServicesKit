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

public protocol SubscriptionManager {

    // Dependencies
    var subscriptionEndpointService: SubscriptionEndpointService { get } // TODO: remove access and handle everything in SubscriptionManager

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

    @available(macOS 12.0, iOS 15.0, *) func storePurchaseManager() -> StorePurchaseManager
    func url(for type: SubscriptionURL) -> URL

    // User
    var isUserAuthenticated: Bool { get }
    var userEmail: String? { get }
    var entitlements: [SubscriptionEntitlement] { get }

    func refreshAccount() async
    func getTokensContainer(policy: TokensCachePolicy) async throws -> TokensContainer
    func exchange(tokenV1: String) async throws -> TokensContainer

    func signOut(skipNotification: Bool)
}

public extension SubscriptionManager {

    func signOut() {
        signOut(skipNotification: false)
    }
}

/// Single entry point for everything related to Subscription. This manager is disposable, every time something related to the environment changes this need to be recreated.
public final class DefaultSubscriptionManager: SubscriptionManager {

    private let oAuthClient: any OAuthClient
    private let _storePurchaseManager: StorePurchaseManager?
    public let subscriptionEndpointService: SubscriptionEndpointService

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
            guard let tokensContainer = try? await oAuthClient.getTokens(policy: .localValid) else {
                completion(false)
                return
            }
            // Refetch and cache subscription
            let subscription = try? await subscriptionEndpointService.getSubscription(accessToken: tokensContainer.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)
            completion(subscription?.isActive ?? false)
        }
    }

    public func currentSubscription(refresh: Bool) async throws -> PrivacyProSubscription {
        let tokensContainer = try await oAuthClient.getTokens(policy: .localValid)
        let subscription = try await subscriptionEndpointService.getSubscription(accessToken: tokensContainer.accessToken, cachePolicy: refresh ? .returnCacheDataElseLoad : .returnCacheDataDontLoad )
        return subscription
    }

    public func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> PrivacyProSubscription {
        let tokensContainer = try await oAuthClient.activate(withPlatformSignature: lastTransactionJWSRepresentation)
        return try await subscriptionEndpointService.getSubscription(accessToken: tokensContainer.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)
    }

    // MARK: - URLs

    public func url(for type: SubscriptionURL) -> URL {
        type.subscriptionURL(environment: currentEnvironment.serviceEnvironment)
    }

    // MARK: - User
    public var isUserAuthenticated: Bool {
        oAuthClient.isUserAuthenticated
    }

    public var userEmail: String? {
        return oAuthClient.currentTokensContainer?.decodedAccessToken.email
    }

    public var entitlements: [SubscriptionEntitlement] {
        return oAuthClient.currentTokensContainer?.decodedAccessToken.subscriptionEntitlements ?? []
    }

    public func refreshAccount() async {
        do {
            let tokensContainer = try await oAuthClient.refreshTokens()
            NotificationCenter.default.post(name: .entitlementsDidChange, object: self, userInfo: nil)
        } catch {
            Logger.subscription.error("Failed to refresh account: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func getTokensContainer(policy: TokensCachePolicy) async throws -> TokensContainer {
        try await oAuthClient.getTokens(policy: policy)
    }

    public func exchange(tokenV1: String) async throws -> TokensContainer {
        try await oAuthClient.exchange(accessTokenV1: tokenV1)
    }

    public func signOut(skipNotification: Bool = false) {
        Logger.subscription.log("Removing all traces of the subscription")
        subscriptionEndpointService.clearSubscription()
        oAuthClient.removeLocalAccount()
//        Task { // TODO: is this needed??
//            do {
//                try await oAuthClient.logout()
//            } catch {
//                Logger.subscription.error("Failed to logout: \(error.localizedDescription, privacy: .public)")
//                return
//            }
//        }
        if !skipNotification {
            NotificationCenter.default.post(name: .accountDidSignOut, object: self, userInfo: nil)
        }
    }

}
