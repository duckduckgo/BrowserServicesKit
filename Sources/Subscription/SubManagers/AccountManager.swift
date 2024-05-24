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

public class AccountManager: AccountManaging {

    private let storage: AccountStoring
    private let entitlementsCache: UserDefaultsCache<[Entitlement]>
    private let accessTokenStorage: SubscriptionTokenStoring
    private let subscriptionService: SubscriptionService
    private let authService: AuthService

    public weak var delegate: AccountManagerKeychainAccessDelegate?
    public var isUserAuthenticated: Bool { accessToken != nil }

    // MARK: - Initialisers

    public init(storage: AccountStoring = AccountKeychainStorage(),
                accessTokenStorage: SubscriptionTokenStoring,
                entitlementsCache: UserDefaultsCache<[Entitlement]>,
                subscriptionService: SubscriptionService,
                authService: AuthService) {
        self.storage = storage
        self.entitlementsCache = entitlementsCache
        self.accessTokenStorage = accessTokenStorage
        self.subscriptionService = subscriptionService
        self.authService = authService
    }

    // MARK: -

    public var authToken: String? {
        do {
            return try storage.getAuthToken()
        } catch {
            if let error = error as? AccountKeychainAccessError {
                delegate?.accountManagerKeychainAccessFailed(accessType: .getAuthToken, error: error)
            } else {
                assertionFailure("Expected AccountKeychainAccessError")
            }

            return nil
        }
    }

    public var accessToken: String? {
        do {
            return try accessTokenStorage.getAccessToken()
        } catch {
            if let error = error as? AccountKeychainAccessError {
                delegate?.accountManagerKeychainAccessFailed(accessType: .getAccessToken, error: error)
            } else {
                assertionFailure("Expected AccountKeychainAccessError")
            }

            return nil
        }
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

    public func storeAuthToken(token: String) {
        os_log(.info, log: .subscription, "[AccountManager] storeAuthToken")

        do {
            try storage.store(authToken: token)
        } catch {
            if let error = error as? AccountKeychainAccessError {
                delegate?.accountManagerKeychainAccessFailed(accessType: .storeAuthToken, error: error)
            } else {
                assertionFailure("Expected AccountKeychainAccessError")
            }
        }
    }

    public func storeAccount(token: String, email: String?, externalID: String?) {
        os_log(.info, log: .subscription, "[AccountManager] storeAccount")

        do {
            try accessTokenStorage.store(accessToken: token)
        } catch {
            if let error = error as? AccountKeychainAccessError {
                delegate?.accountManagerKeychainAccessFailed(accessType: .storeAccessToken, error: error)
            } else {
                assertionFailure("Expected AccountKeychainAccessError")
            }
        }

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

    public func signOut() {
        signOut(skipNotification: false)
    }

    public func signOut(skipNotification: Bool = false) {
        os_log(.info, log: .subscription, "[AccountManager] signOut")

        do {
            try storage.clearAuthenticationState()
            try accessTokenStorage.removeAccessToken()
            subscriptionService.signOut()
            entitlementsCache.reset()
        } catch {
            if let error = error as? AccountKeychainAccessError {
                delegate?.accountManagerKeychainAccessFailed(accessType: .clearAuthenticationData, error: error)
            } else {
                assertionFailure("Expected AccountKeychainAccessError")
            }
        }

        if !skipNotification {
            NotificationCenter.default.post(name: .accountDidSignOut, object: self, userInfo: nil)
        }
    }

    public func migrateAccessTokenToNewStore() throws {
        var errorToThrow: Error?
        do {
            if try accessTokenStorage.getAccessToken() != nil {
                errorToThrow = MigrationError.noMigrationNeeded
            } else if let oldAccessToken = try storage.getAccessToken() {
                try accessTokenStorage.store(accessToken: oldAccessToken)
            }
        } catch {
            errorToThrow = MigrationError.migrationFailed
        }

        if let errorToThrow {
            throw errorToThrow
        }
    }

    public enum MigrationError: Error {
        case migrationFailed
        case noMigrationNeeded
    }

    // MARK: -

    public enum EntitlementsError: Error {
        case noAccessToken
        case noCachedData
    }

    public func hasEntitlement(for entitlement: Entitlement.ProductName, cachePolicy: CachePolicy = .returnCacheDataElseLoad) async -> Result<Bool, Error> {
        switch await fetchEntitlements(cachePolicy: cachePolicy) {
        case .success(let entitlements):
            return .success(entitlements.compactMap { $0.product }.contains(entitlement))
        case .failure(let error):
            return .failure(error)
        }
    }

    public func hasEntitlement(for entitlement: Entitlement.ProductName) async -> Result<Bool, Error> {
        return await hasEntitlement(for: entitlement, cachePolicy: .returnCacheDataElseLoad)
    }

    private func fetchRemoteEntitlements() async -> Result<[Entitlement], Error> {
        guard let accessToken else {
            entitlementsCache.reset()
            return .failure(EntitlementsError.noAccessToken)
        }

        switch await authService.validateToken(accessToken: accessToken) {
        case .success(let response):
            let entitlements = response.account.entitlements
            updateCache(with: entitlements)
            return .success(entitlements)

        case .failure(let error):
            os_log(.error, log: .subscription, "[AccountManager] fetchEntitlements error: %{public}@", error.localizedDescription)
            return .failure(error)
        }
    }

    public func updateCache(with entitlements: [Entitlement]) {
        let cachedEntitlements: [Entitlement] = entitlementsCache.get() ?? []

        if entitlements != cachedEntitlements {
            if entitlements.isEmpty {
                entitlementsCache.reset()
            } else {
                entitlementsCache.set(entitlements)
            }
            NotificationCenter.default.post(name: .entitlementsDidChange, object: self, userInfo: [UserDefaultsCacheKey.subscriptionEntitlements: entitlements])
        }
    }

    @discardableResult
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

    public func fetchAccountDetails(with accessToken: String) async -> Result<AccountDetails, Error> {
        switch await authService.validateToken(accessToken: accessToken) {
        case .success(let response):
            return .success(AccountDetails(email: response.account.email, externalID: response.account.externalID))
        case .failure(let error):
            os_log(.error, log: .subscription, "[AccountManager] fetchAccountDetails error: %{public}@", error.localizedDescription)
            return .failure(error)
        }
    }

    public func refreshSubscriptionAndEntitlements() async {
        os_log(.info, log: .subscription, "[AccountManager] refreshSubscriptionAndEntitlements")

        guard let token = accessToken else {
            subscriptionService.signOut()
            entitlementsCache.reset()
            return
        }

        if case .success(let subscription) = await subscriptionService.getSubscription(accessToken: token, cachePolicy: .reloadIgnoringLocalCacheData) {
            if !subscription.isActive {
                signOut()
            }
        }

        await fetchEntitlements(cachePolicy: .reloadIgnoringLocalCacheData)
    }

    @discardableResult
    public func checkForEntitlements(wait waitTime: Double, retry retryCount: Int) async -> Bool {
        var count = 0
        var hasEntitlements = false

        repeat {
            switch await fetchEntitlements() {
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
