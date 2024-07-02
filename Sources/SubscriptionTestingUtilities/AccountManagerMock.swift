//
//  AccountManagerMock.swift
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
import Subscription

public final class AccountManagerMock: AccountManager {
    public var delegate: AccountManagerKeychainAccessDelegate?
    public var accessToken: String?
    public var authToken: String?
    public var email: String?
    public var externalID: String?

    public init(delegate: AccountManagerKeychainAccessDelegate? = nil,
                accessToken: String? = nil,
                authToken: String? = nil,
                email: String? = nil,
                externalID: String? = nil) {
        self.delegate = delegate
        self.accessToken = accessToken
        self.authToken = authToken
        self.email = email
        self.externalID = externalID
    }

    public func storeAuthToken(token: String) {
        authToken = token
    }

    public func storeAccount(token: String, email: String?, externalID: String?) {
        accessToken = token
    }

    public func signOut(skipNotification: Bool) {
        accessToken = nil
    }

    public func signOut() {
        accessToken = nil
    }

    public func migrateAccessTokenToNewStore() throws {

    }

    public func hasEntitlement(forProductName productName: Entitlement.ProductName, cachePolicy: APICachePolicy) async -> Result<Bool, Error> {
        return .success(true)
    }

    public func updateCache(with entitlements: [Entitlement]) {

    }

    public func fetchEntitlements(cachePolicy: APICachePolicy) async -> Result<[Entitlement], Error> {
        return .success([])
    }

    public func exchangeAuthTokenToAccessToken(_ authToken: String) async -> Result<String, Error> {
        return .success("")
    }

    public func fetchAccountDetails(with accessToken: String) async -> Result<AccountDetails, Error> {
        if let email, let externalID {
            let details: AccountDetails = (email: email, externalID: externalID)
            return .success(details)
        } else {
            return .failure(APIServiceError.unknownServerError)
        }
    }

    public func checkForEntitlements(wait waitTime: Double, retry retryCount: Int) async -> Bool {
        return true
    }
}
