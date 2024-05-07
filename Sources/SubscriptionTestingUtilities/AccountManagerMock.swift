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

class AccountManagerMock: AccountManaging {

    var delegate: AccountManagerKeychainAccessDelegate?
    var isUserAuthenticated: Bool
    var accessToken: String?
    var authToken: String?
    var email: String?
    var externalID: String?

    init(delegate: AccountManagerKeychainAccessDelegate? = nil, isUserAuthenticated: Bool, accessToken: String? = nil, authToken: String? = nil, email: String? = nil, externalID: String? = nil) {
        self.delegate = delegate
        self.isUserAuthenticated = isUserAuthenticated
        self.accessToken = accessToken
        self.authToken = authToken
        self.email = email
        self.externalID = externalID
    }

    func storeAuthToken(token: String) {
        authToken = token
    }

    func storeAccount(token: String, email: String?, externalID: String?) {
        <#code#>
    }

    func signOut(skipNotification: Bool) {
        <#code#>
    }

    func signOut() {
        <#code#>
    }

    func migrateAccessTokenToNewStore() throws {
        <#code#>
    }

    func hasEntitlement(for entitlement: Entitlement.ProductName, cachePolicy: CachePolicy) async -> Result<Bool, Error> {
        <#code#>
    }

    func hasEntitlement(for entitlement: Entitlement.ProductName) async -> Result<Bool, Error> {
        <#code#>
    }

    func updateCache(with entitlements: [Entitlement]) {
        <#code#>
    }

    func fetchEntitlements(cachePolicy: CachePolicy) async -> Result<[Entitlement], Error> {
        <#code#>
    }

    func exchangeAuthTokenToAccessToken(_ authToken: String) async -> Result<String, Error> {
        <#code#>
    }

    func fetchAccountDetails(with accessToken: String) async -> Result<AccountDetails, Error> {
        <#code#>
    }

    func refreshSubscriptionAndEntitlements() async {
        <#code#>
    }

    func checkForEntitlements(wait waitTime: Double, retry retryCount: Int) async -> Bool {
        <#code#>
    }
}
