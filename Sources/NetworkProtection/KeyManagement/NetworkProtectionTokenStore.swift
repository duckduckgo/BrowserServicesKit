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

public protocol NetworkProtectionTokenStore {

    /// Store an auth token.
    ///
    func store(_ token: String) throws

    /// Obtain the current auth token.
    ///
    func fetchToken() throws -> String?

    /// Delete the stored auth token.
    ///
    func deleteToken() throws

    /// Convert DDG-access-token to NetP-auth-token
    ///
    static func makeToken(from accessToken: String) -> String

    /// Check if a given token is derived from DDG-access-token
    ///
    static func isAccessToken(_ token: String) -> Bool
}

/// Store an auth token for NetworkProtection on behalf of the user. This key is then used to authenticate requests for registration and server fetches from the Network Protection backend servers.
/// Writing a new auth token will replace the old one.
public final class NetworkProtectionKeychainTokenStore: NetworkProtectionTokenStore {
    private let keychainStore: NetworkProtectionKeychainStore
    private let errorEvents: EventMapping<NetworkProtectionError>?
    private let isSubscriptionEnabled: Bool

    public struct Defaults {
        static let tokenStoreEntryLabel = "DuckDuckGo Network Protection Auth Token"
        public static let tokenStoreService = "com.duckduckgo.networkprotection.authToken"
        static let tokenStoreName = "com.duckduckgo.networkprotection.token"
    }

    public init(keychainType: KeychainType,
                serviceName: String = Defaults.tokenStoreService,
                errorEvents: EventMapping<NetworkProtectionError>?,
                isSubscriptionEnabled: Bool) {
        keychainStore = NetworkProtectionKeychainStore(label: Defaults.tokenStoreEntryLabel,
                                                       serviceName: serviceName,
                                                       keychainType: keychainType)
        self.errorEvents = errorEvents
        self.isSubscriptionEnabled = isSubscriptionEnabled
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
            // Skip deleting DDG-access-token as it's used for entitlement validity check
            guard isSubscriptionEnabled, let token = try? fetchToken(), !Self.isAccessToken(token) else { return }
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

extension NetworkProtectionTokenStore {
    private static var authTokenPrefix: String { "ddg:" }

    public static func makeToken(from accessToken: String) -> String {
        "\(authTokenPrefix)\(accessToken)"
    }

    public static func isAccessToken(_ token: String) -> Bool {
        token.hasPrefix(authTokenPrefix)
    }
}
