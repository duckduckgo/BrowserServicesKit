//
//  AccountManager.swift
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
import Common

public extension Notification.Name {
    static let accountDidSignIn = Notification.Name("com.duckduckgo.subscription.AccountDidSignIn")
    static let accountDidSignOut = Notification.Name("com.duckduckgo.subscription.AccountDidSignOut")
    static let entitlementsDidChange = Notification.Name("com.duckduckgo.subscription.EntitlementsDidChange")
}

public protocol AccountManagerKeychainAccessDelegate: AnyObject {
    func accountManagerKeychainAccessFailed(accessType: AccountKeychainAccessType, error: AccountKeychainAccessError)
}

public typealias AccountDetails = (email: String?, externalID: String)

public protocol AccountManaging {

    var email: String? { get }
    var externalID: String? { get }

    func storeAccount(token: String, email: String?, externalID: String?)

    func exchangeAuthTokenToAccessToken(_ authToken: String) async -> Result<String, Error>
    func fetchAccountDetails(with accessToken: String) async -> Result<AccountDetails, Error>
    func checkSubscriptionState() async

    func hasEntitlement(for entitlement: Entitlement.ProductName) async -> Result<Bool, Error>
    func hasEntitlement(for entitlement: Entitlement.ProductName, cachePolicy: CachePolicy) async -> Result<Bool, Error>

    func checkForEntitlements(wait waitTime: Double, retry retryCount: Int) async -> Bool
}

public class AccountManager: AccountManaging {

    private let storage: AccountStorage
    private let entitlementsCache: UserDefaultsCache<[Entitlement]>

    public weak var delegate: AccountManagerKeychainAccessDelegate?

    private let authService: AuthServiceProtocol
    private let subscriptionService: SubscriptionServiceProtocol

    public convenience init(subscriptionAppGroup: String, authService: AuthServiceProtocol, subscriptionService: SubscriptionServiceProtocol) {
        self.init(entitlementsCache: UserDefaultsCache<[Entitlement]>(subscriptionAppGroup: subscriptionAppGroup, key: UserDefaultsCacheKey.subscriptionEntitlements),
                  authService: authService,
                  subscriptionService: subscriptionService)
    }

    public init(storage: AccountStorage = AccountKeychainStorage(),
                entitlementsCache: UserDefaultsCache<[Entitlement]>,
                authService: AuthServiceProtocol,
                subscriptionService: SubscriptionServiceProtocol) {
        self.storage = storage
        self.entitlementsCache = entitlementsCache
        self.authService = authService
        self.subscriptionService = subscriptionService
    }

    public var email: String? {
        do {
            return try storage.getEmail()
        } catch {
            if let error = error as? AccountKeychainAccessError {
                delegate?.accountManagerKeychainAccessFailed(accessType: .getEmail, error: error)
            } else {
                assertionFailure("Expected AccountKeychainAccessError")
            }

            return nil
        }
    }

    public var externalID: String? {
        do {
            return try storage.getExternalID()
        } catch {
            if let error = error as? AccountKeychainAccessError {
                delegate?.accountManagerKeychainAccessFailed(accessType: .getExternalID, error: error)
            } else {
                assertionFailure("Expected AccountKeychainAccessError")
            }

            return nil
        }
    }

//    public func storeAuthToken(token: String) {
//        os_log(.info, log: .subscription, "[AccountManager] storeAuthToken")
//        tokenStorage.authToken = token
//    }

    public func storeAccount(token: String, email: String?, externalID: String?) {
        os_log(.info, log: .subscription, "[AccountManager] storeAccount")

//        tokenStorage.accessToken = token

        do {
            try storage.store(email: email)
        } catch {
            if let error = error as? AccountKeychainAccessError {
                delegate?.accountManagerKeychainAccessFailed(accessType: .storeEmail, error: error)
            } else {
                assertionFailure("Expected AccountKeychainAccessError")
            }
        }

        do {
            try storage.store(externalID: externalID)
        } catch {
            if let error = error as? AccountKeychainAccessError {
                delegate?.accountManagerKeychainAccessFailed(accessType: .storeExternalID, error: error)
            } else {
                assertionFailure("Expected AccountKeychainAccessError")
            }
        }
        NotificationCenter.default.post(name: .accountDidSignIn, object: self, userInfo: nil)
    }

    // MARK: -

    public enum EntitlementsError: Error {
        case noAccessToken
        case noCachedData
    }

    public func hasEntitlement(for entitlement: Entitlement.ProductName) async -> Result<Bool, Error> {
        return await hasEntitlement(for: entitlement, cachePolicy: .returnCacheDataElseLoad)
    }

    public func hasEntitlement(for entitlement: Entitlement.ProductName, cachePolicy: CachePolicy) async -> Result<Bool, Error> {
        switch await fetchEntitlements(cachePolicy: cachePolicy) {
        case .success(let entitlements):
            return .success(entitlements.compactMap { $0.product }.contains(entitlement))
        case .failure(let error):
            return .failure(error)
        }
    }

    private func fetchRemoteEntitlements() async -> Result<[Entitlement], Error> {
        let accessToken = "TODO: Fix me"
//        guard let accessToken = tokenStorage.accessToken else {
//            entitlementsCache.reset()
//            return .failure(EntitlementsError.noAccessToken)
//        }

        let cachedEntitlements: [Entitlement]? = entitlementsCache.get()

        switch await authService.validateToken(accessToken: accessToken) {
        case .success(let response):
            let entitlements = response.account.entitlements
            if entitlements != cachedEntitlements {
                entitlementsCache.set(entitlements)
                NotificationCenter.default.post(name: .entitlementsDidChange, object: self, userInfo: [UserDefaultsCacheKey.subscriptionEntitlements: entitlements])
            }
            return .success(entitlements)

        case .failure(let error):
            os_log(.error, log: .subscription, "[AccountManager] fetchEntitlements error: %{public}@", error.localizedDescription)
            return .failure(error)
        }
    }

    public func fetchEntitlements(cachePolicy: CachePolicy = .returnCacheDataElseLoad) async -> Result<[Entitlement], Error> {

        switch cachePolicy {
        case .reloadIgnoringLocalCacheData:
            return await fetchRemoteEntitlements()

        case .returnCacheDataElseLoad:
            if let cachedEntitlements: [Entitlement] = entitlementsCache.get() {
                return .success(cachedEntitlements)
            } else {
                return await fetchRemoteEntitlements()
            }

        case .returnCacheDataDontLoad:
            if let cachedEntitlements: [Entitlement] = entitlementsCache.get() {
                return .success(cachedEntitlements)
            } else {
                return .failure(EntitlementsError.noCachedData)
            }
        }

    }

    public func exchangeAuthTokenToAccessToken(_ authToken: String) async -> Result<String, Error> {
        switch await authService.getAccessToken(token: authToken) {
        case .success(let response):
            return .success(response.accessToken)
        case .failure(let error):
            os_log(.error, log: .subscription, "[AccountManager] exchangeAuthTokenToAccessToken error: %{public}@", error.localizedDescription)
            return .failure(error)
        }
    }

    public typealias AccountDetails = (email: String?, externalID: String)

    public func fetchAccountDetails(with accessToken: String) async -> Result<AccountDetails, Error> {
        switch await authService.validateToken(accessToken: accessToken) {
        case .success(let response):
            return .success(AccountDetails(email: response.account.email, externalID: response.account.externalID))
        case .failure(let error):
            os_log(.error, log: .subscription, "[AccountManager] fetchAccountDetails error: %{public}@", error.localizedDescription)
            return .failure(error)
        }
    }

    public func checkSubscriptionState() async {
        os_log(.info, log: .subscription, "[AccountManager] checkSubscriptionState")

        let token = "TODO: Fix me"
//        guard let token = tokenStorage.accessToken else { return }

        if case .success(let subscription) = await subscriptionService.getSubscription(accessToken: token) {
            if !subscription.isActive {
//                signOut()
            }
        }
    }

    @discardableResult
    public func checkForEntitlements(wait waitTime: Double, retry retryCount: Int) async -> Bool {
        var count = 0
        var hasEntitlements = false

        repeat {
            switch await fetchEntitlements(cachePolicy: .reloadIgnoringLocalCacheData) {
            case .success(let entitlements):
                hasEntitlements = !entitlements.isEmpty
            case .failure:
                hasEntitlements = false
            }

            if hasEntitlements {
                break
            } else {
                count += 1
                try? await Task.sleep(seconds: waitTime)
            }
        } while !hasEntitlements && count < retryCount

        return hasEntitlements
    }
}

extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: Double) async throws {
        let duration = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: duration)
    }
}
