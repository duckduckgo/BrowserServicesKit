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

//public protocol SubscriptionManagerTokenProviding {
//
//    func getTokens() async throws -> TokensContainer
//    func refreshTokens() async throws
//    func logout()
//}

public protocol SubscriptionManager {

    // Dependencies
    var subscriptionEndpointService: SubscriptionEndpointService { get }

    // Environment
    static func loadEnvironmentFrom(userDefaults: UserDefaults) -> SubscriptionEnvironment?
    static func save(subscriptionEnvironment: SubscriptionEnvironment, userDefaults: UserDefaults)
    var currentEnvironment: SubscriptionEnvironment { get }

    var canPurchase: Bool { get }
    @available(macOS 12.0, iOS 15.0, *) func storePurchaseManager() -> StorePurchaseManager
//    func loadInitialData()
    func refreshCachedSubscription(completion: @escaping (_ isSubscriptionActive: Bool) -> Void)
    func url(for type: SubscriptionURL) -> URL

    // User
    var isUserAuthenticated: Bool { get }
    var userEmail: String? { get }
    var entitlements: [SubscriptionEntitlement] { get }

    func refreshAccount()
    func getTokens(policy: TokensCachePolicy) async throws -> TokensContainer

    func signOut()
    func signOut(skipNotification: Bool)
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

    // MARK: -

//    public func loadInitialData() {
//        Task {
//            let tokensContainer = try await oAuthClient.getValidAccessToken()
//            _ = await subscriptionEndpointService.getSubscription(accessToken: tokensContainer.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)
//            //            _ = await accountManager.fetchEntitlements(cachePolicy: .reloadIgnoringLocalCacheData)
//        }
//    }

    public func refreshCachedSubscription(completion: @escaping (_ isSubscriptionActive: Bool) -> Void) {
        Task {
            let tokensContainer = try await oAuthClient.getTokens(policy: .valid)
            // Refetch and cache subscription
            let subscription = try? await subscriptionEndpointService.getSubscription(accessToken: tokensContainer.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)
            completion(subscription?.isActive ?? false)
        }
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

    public func refreshAccount() {
        Task {
            try? await oAuthClient.refreshTokens()
        }
    }

    public func getTokens(policy: TokensCachePolicy) async throws -> TokensContainer {
        try await oAuthClient.getTokens(policy: policy)
    }

    public func signOut() {
        signOut(skipNotification: false)
    }

    public func signOut(skipNotification: Bool = false) {
        Logger.subscription.debug("SignOut")
        Task {
            do {
                try await oAuthClient.logout()
                //            try storage.clearAuthenticationState()
                //            try accessTokenStorage.removeAccessToken()
                subscriptionEndpointService.signOut()
//                entitlementsCache.reset()
            } catch {
                Logger.subscription.error("\(error.localizedDescription)")
                assertionFailure(error.localizedDescription)
            }

            if !skipNotification {
                NotificationCenter.default.post(name: .accountDidSignOut, object: self, userInfo: nil)
            }
        }
    }

}
