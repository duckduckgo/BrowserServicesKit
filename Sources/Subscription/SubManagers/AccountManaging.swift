//
//  AccountManaging.swift
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

public protocol AccountManagerKeychainAccessDelegate: AnyObject {
    func accountManagerKeychainAccessFailed(accessType: AccountKeychainAccessType, error: AccountKeychainAccessError)
}

public enum AccountManagingCachePolicy {
    case reloadIgnoringLocalCacheData
    case returnCacheDataElseLoad
    case returnCacheDataDontLoad
}

public protocol AccountManaging {

    var delegate: AccountManagerKeychainAccessDelegate? { get set }
    var isUserAuthenticated: Bool { get }
    var accessToken: String? { get }
    var authToken: String? { get }
    var email: String? { get }
    var externalID: String? { get }

    func storeAuthToken(token: String)
    func storeAccount(token: String, email: String?, externalID: String?)
    func signOut(skipNotification: Bool)
    func signOut()
    func migrateAccessTokenToNewStore() throws

    // Entitlements
    typealias CachePolicy = AccountManagingCachePolicy
    func hasEntitlement(for entitlement: Entitlement.ProductName, cachePolicy: CachePolicy) async -> Result<Bool, Error>
    func hasEntitlement(for entitlement: Entitlement.ProductName) async -> Result<Bool, Error>
    func updateCache(with entitlements: [Entitlement])
    @discardableResult func fetchEntitlements(cachePolicy: CachePolicy) async -> Result<[Entitlement], Error>
    func exchangeAuthTokenToAccessToken(_ authToken: String) async -> Result<String, Error>

    typealias AccountDetails = (email: String?, externalID: String)
    func fetchAccountDetails(with accessToken: String) async -> Result<AccountDetails, Error>
    func refreshSubscriptionAndEntitlements() async
    @discardableResult func checkForEntitlements(wait waitTime: Double, retry retryCount: Int) async -> Bool
}
