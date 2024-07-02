//
//  AccountManagerTests.swift
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

import XCTest
@testable import Subscription
import SubscriptionTestingUtilities
import Common

final class AccountManagerTests: XCTestCase {

    var userDefaults: UserDefaults!
    let testGroupName = "com.ddg.unitTests.AccountManagerTests"

    override func setUpWithError() throws {
        userDefaults = UserDefaults(suiteName: testGroupName)!
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: testGroupName)
    }

    func testExample() throws {
        let accessToken = "someAccessToken"
        let storage = AccountKeychainStorageMock()
        let accessTokenStorage = SubscriptionTokenKeychainStorageMock()
        let entitlementsCache = UserDefaultsCache<[Entitlement]>(userDefaults: userDefaults,
                                                                 key: UserDefaultsCacheKey.subscriptionEntitlements,
                                                                 settings: UserDefaultsCacheSettings(defaultExpirationInterval: .minutes(20)))
        let accountManager = DefaultAccountManager(storage: storage,
                                                   accessTokenStorage: accessTokenStorage,
                                                   entitlementsCache: entitlementsCache,
                                                   subscriptionEndpointService: SubscriptionMockFactory.subscriptionEndpointService,
                                                   authEndpointService: SubscriptionMockFactory.authEndpointService)

        accountManager.storeAccount(token: accessToken, email: SubscriptionMockFactory.email, externalID: SubscriptionMockFactory.externalId)
        XCTAssertEqual(accessTokenStorage.accessToken, accessToken)
        XCTAssertEqual(storage.email, SubscriptionMockFactory.email)
        XCTAssertEqual(storage.externalID, SubscriptionMockFactory.externalId)
    }
}
