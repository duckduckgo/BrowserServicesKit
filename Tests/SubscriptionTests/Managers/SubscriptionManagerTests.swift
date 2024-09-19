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
        static let userDefaultsSuiteName = "SubscriptionManagerTests"

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
        subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production,
                                                          purchasePlatform: .appStore)

        subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                         accountManager: accountManager,
                                                         subscriptionEndpointService: subscriptionService,
                                                         authEndpointService: authService,
                                                         subscriptionEnvironment: subscriptionEnvironment)

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
        // Given
        let userDefaults = UserDefaults(suiteName: Constants.userDefaultsSuiteName)!
        userDefaults.removePersistentDomain(forName: Constants.userDefaultsSuiteName)

        var loadedEnvironment = DefaultSubscriptionManager.loadEnvironmentFrom(userDefaults: userDefaults)
        XCTAssertNil(loadedEnvironment)

        // When
        DefaultSubscriptionManager.save(subscriptionEnvironment: subscriptionEnvironment,
                                        userDefaults: userDefaults)
        loadedEnvironment = DefaultSubscriptionManager.loadEnvironmentFrom(userDefaults: userDefaults)

        // Then
        XCTAssertEqual(loadedEnvironment?.serviceEnvironment, subscriptionEnvironment.serviceEnvironment)
        XCTAssertEqual(loadedEnvironment?.purchasePlatform, subscriptionEnvironment.purchasePlatform)
    }

    // MARK: - Tests for setup for App Store

    func testSetupForAppStore() async throws {
        // Given
        storePurchaseManager.onUpdateAvailableProducts = {
            self.storePurchaseManager.areProductsAvailable = true
        }

        // When
        // triggered on DefaultSubscriptionManager's init
        try await Task.sleep(seconds: 0.5)

        // Then
        XCTAssertTrue(storePurchaseManager.updateAvailableProductsCalled)
        XCTAssertTrue(subscriptionManager.canPurchase)
    }

    // MARK: - Tests for loadInitialData

    func testLoadInitialData() async throws {
        // Given
        accountManager.accessToken = Constants.accessToken

        subscriptionService.onGetSubscription = { _, cachePolicy in
            XCTAssertEqual(cachePolicy, .reloadIgnoringLocalCacheData)
        }
        subscriptionService.getSubscriptionResult = .success(SubscriptionMockFactory.subscription)

        accountManager.onFetchEntitlements = { cachePolicy in
            XCTAssertEqual(cachePolicy, .reloadIgnoringLocalCacheData)
        }

        // When
        subscriptionManager.loadInitialData()

        try await Task.sleep(seconds: 0.5)

        // Then
        XCTAssertTrue(subscriptionService.getSubscriptionCalled)
        XCTAssertTrue(accountManager.fetchEntitlementsCalled)
    }

    func testLoadInitialDataNotCalledWhenUnauthenticated() async throws {
        // Given
        XCTAssertNil(accountManager.accessToken)
        XCTAssertFalse(accountManager.isUserAuthenticated)

        // When
        subscriptionManager.loadInitialData()

        // Then
        XCTAssertFalse(subscriptionService.getSubscriptionCalled)
        XCTAssertFalse(accountManager.fetchEntitlementsCalled)
    }

    // MARK: - Tests for refreshCachedSubscriptionAndEntitlements

    func testForRefreshCachedSubscriptionAndEntitlements() async throws {
        // Given
        let subscription = SubscriptionMockFactory.subscription

        accountManager.accessToken = Constants.accessToken

        subscriptionService.onGetSubscription = { _, cachePolicy in
            XCTAssertEqual(cachePolicy, .reloadIgnoringLocalCacheData)
        }
        subscriptionService.getSubscriptionResult = .success(subscription)

        accountManager.onFetchEntitlements = { cachePolicy in
            XCTAssertEqual(cachePolicy, .reloadIgnoringLocalCacheData)
        }

        // When
        let completionCalled = expectation(description: "completion called")
        subscriptionManager.refreshCachedSubscriptionAndEntitlements { isSubscriptionActive in
            completionCalled.fulfill()
            XCTAssertEqual(isSubscriptionActive, subscription.isActive)
        }

        // Then
        await fulfillment(of: [completionCalled], timeout: 0.5)
        XCTAssertTrue(subscriptionService.getSubscriptionCalled)
        XCTAssertTrue(accountManager.fetchEntitlementsCalled)
    }

    func testForRefreshCachedSubscriptionAndEntitlementsSignOutUserOn401() async throws {
        // Given
        accountManager.accessToken = Constants.accessToken

        subscriptionService.onGetSubscription = { _, cachePolicy in
            XCTAssertEqual(cachePolicy, .reloadIgnoringLocalCacheData)
        }
        subscriptionService.getSubscriptionResult = .failure(.apiError(Constants.invalidTokenError))

        // When
        let completionCalled = expectation(description: "completion called")
        subscriptionManager.refreshCachedSubscriptionAndEntitlements { isSubscriptionActive in
            completionCalled.fulfill()
            XCTAssertFalse(isSubscriptionActive)
        }

        // Then
        await fulfillment(of: [completionCalled], timeout: 0.5)
        XCTAssertTrue(accountManager.signOutCalled)
        XCTAssertTrue(subscriptionService.getSubscriptionCalled)
        XCTAssertFalse(accountManager.fetchEntitlementsCalled)
    }

    // MARK: - Tests for url

    func testForProductionURL() throws {
        // Given
        let productionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)

        let productionSubscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                                       accountManager: accountManager,
                                                                       subscriptionEndpointService: subscriptionService,
                                                                       authEndpointService: authService,
                                                                       subscriptionEnvironment: productionEnvironment)

        // When
        let productionPurchaseURL = productionSubscriptionManager.url(for: .purchase)

        // Then
        XCTAssertEqual(productionPurchaseURL, SubscriptionURL.purchase.subscriptionURL(environment: .production))
    }

    func testForStagingURL() throws {
        // Given
        let stagingEnvironment = SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .appStore)

        let stagingSubscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                                    accountManager: accountManager,
                                                                    subscriptionEndpointService: subscriptionService,
                                                                    authEndpointService: authService,
                                                                    subscriptionEnvironment: stagingEnvironment)

        // When
        let stagingPurchaseURL = stagingSubscriptionManager.url(for: .purchase)

        // Then
        XCTAssertEqual(stagingPurchaseURL, SubscriptionURL.purchase.subscriptionURL(environment: .staging))
    }
}
