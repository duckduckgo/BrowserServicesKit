//
//  SubscriptionManagerTests.swift
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

final class SubscriptionManagerTests: XCTestCase {

    private struct Constants {
        static let accessToken = UUID().uuidString

        static let invalidTokenError = APIServiceError.serverError(statusCode: 401, error: "invalid_token")
    }

    var storePurchaseManager: StorePurchaseManagerMock!
    var accountManager: AccountManagerMock!
    var subscriptionService: SubscriptionEndpointServiceMock!
    var authService: AuthEndpointServiceMock!
    var subscriptionEnvironment: SubscriptionEnvironment!

    var subscriptionManager: SubscriptionManager!

    override func setUpWithError() throws {
        storePurchaseManager = StorePurchaseManagerMock()
        accountManager = AccountManagerMock()
        subscriptionService = SubscriptionEndpointServiceMock()
        authService = AuthEndpointServiceMock()
    }

    override func tearDownWithError() throws {
        storePurchaseManager = nil
        accountManager = nil
        subscriptionService = nil
        authService = nil
        subscriptionEnvironment = nil

        subscriptionManager = nil
    }

    // MARK: - Tests for save and loadEnvironmentFrom

    func testLoadEnvironmentFromUserDefaults() async throws {
        let userDefaults = UserDefaults(suiteName: #file)!
        userDefaults.removePersistentDomain(forName: #file)

        var loadedEnvironment = DefaultSubscriptionManager.loadEnvironmentFrom(userDefaults: userDefaults)
        XCTAssertNil(loadedEnvironment)

        let subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, 
                                                              purchasePlatform: .appStore)

        DefaultSubscriptionManager.save(subscriptionEnvironment: subscriptionEnvironment, 
                                        userDefaults: userDefaults)
        
        loadedEnvironment = DefaultSubscriptionManager.loadEnvironmentFrom(userDefaults: userDefaults)
        XCTAssertEqual(loadedEnvironment?.serviceEnvironment, subscriptionEnvironment.serviceEnvironment)
        XCTAssertEqual(loadedEnvironment?.purchasePlatform, subscriptionEnvironment.purchasePlatform)
    }

    // MARK: - Tests for setup for App Store

    func testSetupForAppStore() async throws {
        storePurchaseManager.onUpdateAvailableProducts = {
            self.storePurchaseManager.areProductsAvailable = true
        }

        subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)

        subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                         accountManager: accountManager,
                                                         subscriptionEndpointService: subscriptionService,
                                                         authEndpointService: authService,
                                                         subscriptionEnvironment: subscriptionEnvironment)

        XCTAssertTrue(storePurchaseManager.updateAvailableProductsCalled)
        XCTAssertTrue(subscriptionManager.canPurchase)
    }

    // MARK: - Tests for loadInitialData

    func testLoadInitialData() async throws {
        accountManager.accessToken = Constants.accessToken

        let getSubscriptionCalled = expectation(description: "getSubscriptionCalled called")
        subscriptionService.onGetSubscriptionCalled = { _, cachePolicy in
            XCTAssertEqual(cachePolicy, .reloadIgnoringLocalCacheData)
            getSubscriptionCalled.fulfill()
        }
        subscriptionService.getSubscriptionResult = .success(SubscriptionMockFactory.subscription)

        let fetchEntitlementsCalled = expectation(description: "fetchEntitlements called")
        accountManager.onFetchEntitlements = { cachePolicy in
            XCTAssertEqual(cachePolicy, .reloadIgnoringLocalCacheData)
            fetchEntitlementsCalled.fulfill()
        }

        subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)

        subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                         accountManager: accountManager,
                                                         subscriptionEndpointService: subscriptionService,
                                                         authEndpointService: authService,
                                                         subscriptionEnvironment: subscriptionEnvironment)
        subscriptionManager.loadInitialData()

        await fulfillment(of: [getSubscriptionCalled, fetchEntitlementsCalled], timeout: 0.5)
    }

    func testLoadInitialDataNotCalledWhenUnauthenticated() async throws {
        XCTAssertNil(accountManager.accessToken)
        XCTAssertFalse(accountManager.isUserAuthenticated)

        let getSubscriptionCalled = expectation(description: "getSubscriptionCalled called")
        getSubscriptionCalled.isInverted = true
        subscriptionService.onGetSubscriptionCalled = { _, cachePolicy in
            getSubscriptionCalled.fulfill()
        }

        let fetchEntitlementsCalled = expectation(description: "fetchEntitlements called")
        fetchEntitlementsCalled.isInverted = true
        accountManager.onFetchEntitlements = { cachePolicy in
            fetchEntitlementsCalled.fulfill()
        }

        subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)

        subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                         accountManager: accountManager,
                                                         subscriptionEndpointService: subscriptionService,
                                                         authEndpointService: authService,
                                                         subscriptionEnvironment: subscriptionEnvironment)
        subscriptionManager.loadInitialData()

        await fulfillment(of: [getSubscriptionCalled, fetchEntitlementsCalled], timeout: 0.5)
    }

    // MARK: - Tests for refreshCachedSubscriptionAndEntitlements

    func testForRefreshCachedSubscriptionAndEntitlements() async throws {
        let subscription = SubscriptionMockFactory.subscription

        accountManager.accessToken = Constants.accessToken

        let getSubscriptionCalled = expectation(description: "getSubscriptionCalled called")
        subscriptionService.onGetSubscriptionCalled = { _, cachePolicy in
            XCTAssertEqual(cachePolicy, .reloadIgnoringLocalCacheData)
            getSubscriptionCalled.fulfill()
        }
        subscriptionService.getSubscriptionResult = .success(subscription)

        let fetchEntitlementsCalled = expectation(description: "fetchEntitlements called")
        accountManager.onFetchEntitlements = { cachePolicy in
            XCTAssertEqual(cachePolicy, .reloadIgnoringLocalCacheData)
            fetchEntitlementsCalled.fulfill()
        }

        subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)

        subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                         accountManager: accountManager,
                                                         subscriptionEndpointService: subscriptionService,
                                                         authEndpointService: authService,
                                                         subscriptionEnvironment: subscriptionEnvironment)

        let completionCalled = expectation(description: "completion called")
        subscriptionManager.refreshCachedSubscriptionAndEntitlements { isSubscriptionActive in
            completionCalled.fulfill()
            XCTAssertEqual(isSubscriptionActive, subscription.isActive)
        }

        await fulfillment(of: [getSubscriptionCalled, fetchEntitlementsCalled, completionCalled], timeout: 0.5)
    }

    func testForRefreshCachedSubscriptionAndEntitlementsSignOutUserOn401() async throws {
        accountManager.accessToken = Constants.accessToken

        let getSubscriptionCalled = expectation(description: "getSubscriptionCalled called")
        subscriptionService.onGetSubscriptionCalled = { _, cachePolicy in
            XCTAssertEqual(cachePolicy, .reloadIgnoringLocalCacheData)
            getSubscriptionCalled.fulfill()
        }
        subscriptionService.getSubscriptionResult = .failure(.apiError(Constants.invalidTokenError))

        let signOutCalled = expectation(description: "signOut called")
        accountManager.onSignOut = {
            signOutCalled.fulfill()
        }

        subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)

        subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                         accountManager: accountManager,
                                                         subscriptionEndpointService: subscriptionService,
                                                         authEndpointService: authService,
                                                         subscriptionEnvironment: subscriptionEnvironment)

        let completionCalled = expectation(description: "completion called")
        subscriptionManager.refreshCachedSubscriptionAndEntitlements { isSubscriptionActive in
            completionCalled.fulfill()
            XCTAssertFalse(isSubscriptionActive)
        }

        await fulfillment(of: [getSubscriptionCalled, signOutCalled, completionCalled], timeout: 0.5)
    }

    // MARK: - Tests for url

    func testForProductionURL() throws {
        subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)

        subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                         accountManager: accountManager,
                                                         subscriptionEndpointService: subscriptionService,
                                                         authEndpointService: authService,
                                                         subscriptionEnvironment: subscriptionEnvironment)
        
        XCTAssertEqual(subscriptionManager.url(for: .purchase), SubscriptionURL.purchase.subscriptionURL(environment: .production))
    }

    func testForStagingURL() throws {
        subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .appStore)

        subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                         accountManager: accountManager,
                                                         subscriptionEndpointService: subscriptionService,
                                                         authEndpointService: authService,
                                                         subscriptionEnvironment: subscriptionEnvironment)

        XCTAssertEqual(subscriptionManager.url(for: .purchase), SubscriptionURL.purchase.subscriptionURL(environment: .staging))
    }
}
