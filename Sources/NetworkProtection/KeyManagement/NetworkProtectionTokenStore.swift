//
//  NetworkProtectionTokenStore.swift
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
import Subscription

public protocol NetworkProtectionTokenStore {
    /// Fetch the access token from the subscription library and convert it into a NetP auth token
    ///
    func fetchSubscriptionToken() throws -> String?

    /// Store an auth token.
    ///
    @available(*, deprecated, message: "[NetP Subscription] Do not manually manage auth token")
    func store(_ token: String) throws

    /// Obtain the current auth token.
    ///
    @available(*, deprecated, renamed: "fetchSubscriptionToken")
    func fetchToken() throws -> String?

    /// Delete the stored auth token.
    ///
    @available(*, deprecated, message: "[NetP Subscription] Do not manually manage auth token")
    func deleteToken() throws
}

/// Store an auth token for NetworkProtection on behalf of the user. This key is then used to authenticate requests for registration and server fetches from the Network Protection backend servers.
/// Writing a new auth token will replace the old one.
public final class NetworkProtectionKeychainTokenStore: NetworkProtectionTokenStore {
    private let keychainStore: NetworkProtectionKeychainStore
    private let errorEvents: EventMapping<NetworkProtectionError>?
    private let isSubscriptionEnabled: Bool
    private let accountManager: AccountManaging

    public func fetchSubscriptionToken() throws -> String? {
        if isSubscriptionEnabled, let accessToken = accountManager.accessToken {
            return makeToken(from: accessToken)
        }

        return try fetchToken()
    }

    private static var authTokenPrefix: String { "ddg:" }

    private func makeToken(from subscriptionAccessToken: String) -> String {
        Self.authTokenPrefix + subscriptionAccessToken
    }

    // MARK: - Deprecated stuff

    public struct Defaults {
        static let tokenStoreEntryLabel = "DuckDuckGo Network Protection Auth Token"
        public static let tokenStoreService = "com.duckduckgo.networkprotection.authToken"
        static let tokenStoreName = "com.duckduckgo.networkprotection.token"
    }

    public init(keychainType: KeychainType,
                serviceName: String = Defaults.tokenStoreService,
                errorEvents: EventMapping<NetworkProtectionError>?,
                isSubscriptionEnabled: Bool,
                subscriptionAppGroup: String) {
        keychainStore = NetworkProtectionKeychainStore(label: Defaults.tokenStoreEntryLabel,
                                                       serviceName: serviceName,
                                                       keychainType: keychainType)
        self.errorEvents = errorEvents
        self.isSubscriptionEnabled = isSubscriptionEnabled
        self.accountManager = AccountManager(subscriptionAppGroup: subscriptionAppGroup)
    }

    public func store(_ token: String) throws {
        let data = token.data(using: .utf8)!
        do {
            try keychainStore.writeData(data, named: Defaults.tokenStoreName)
        } catch {
            handle(error)
            throw error
        }
    }

    public func fetchToken() throws -> String? {
        do {
            return try keychainStore.readData(named: Defaults.tokenStoreName).flatMap {
                String(data: $0, encoding: .utf8)
            }
        } catch {
            handle(error)
            throw error
        }
    }

    public func deleteToken() throws {
        do {
            try keychainStore.deleteAll()
        } catch {
            handle(error)
            throw error
        }
    }

    // MARK: - EventMapping

    private func handle(_ error: Error) {
        guard let error = error as? NetworkProtectionKeychainStoreError else {
            assertionFailure("Failed to cast Network Protection Token store error")
            errorEvents?.fire(NetworkProtectionError.unhandledError(function: #function, line: #line, error: error))
            return
        }

        errorEvents?.fire(error.networkProtectionError)
    }
}
