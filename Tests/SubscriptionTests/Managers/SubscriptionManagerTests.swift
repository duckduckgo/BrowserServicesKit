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
@testable import Networking
import SubscriptionTestingUtilities
import TestUtils

class SubscriptionManagerTests: XCTestCase {

    var subscriptionManager: DefaultSubscriptionManager!
    var mockOAuthClient: MockOAuthClient!
    var mockSubscriptionEndpointService: SubscriptionEndpointServiceMock!
    var mockStorePurchaseManager: StorePurchaseManagerMock!
    var subscriptionFeatureFlagger: FeatureFlaggerMapping<SubscriptionFeatureFlags>!

    override func setUp() {
        super.setUp()

        mockOAuthClient = MockOAuthClient()
        mockSubscriptionEndpointService = SubscriptionEndpointServiceMock()
        mockStorePurchaseManager = StorePurchaseManagerMock()
        subscriptionFeatureFlagger = FeatureFlaggerMapping<SubscriptionFeatureFlags>(mapping: { $0.defaultState })

        subscriptionManager = DefaultSubscriptionManager(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .stripe),
            subscriptionFeatureFlagger: subscriptionFeatureFlagger,
            pixelHandler: { _ in }
        )
    }

    override func tearDown() {
        subscriptionManager = nil
        mockOAuthClient = nil
        mockSubscriptionEndpointService = nil
        mockStorePurchaseManager = nil
        super.tearDown()
    }

    // MARK: - Token Retrieval Tests

    func testGetTokenContainer_Success() async throws {
        let expectedTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .success(expectedTokenContainer)

        let result = try await subscriptionManager.getTokenContainer(policy: .localValid)
        XCTAssertEqual(result, expectedTokenContainer)
    }

    func testGetTokenContainer_ErrorHandlingDeadToken() async throws {
        // Set up dead token error to trigger recovery attempt
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.deadToken)
        let date = Date()
        let expiredSubscription = PrivacyProSubscription(
            productId: "testProduct",
            name: "Test Subscription",
            billingPeriod: .monthly,
            startedAt: date.addingTimeInterval(-30 * 24 * 60 * 60), // 30 days ago
            expiresOrRenewsAt: date.addingTimeInterval(-1), // expired
            platform: .apple,
            status: .expired
        )
        mockSubscriptionEndpointService.getSubscriptionResult = .success(expiredSubscription)
        let expectation = self.expectation(description: "Dead token pixel called")
        subscriptionManager = DefaultSubscriptionManager(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .stripe),
            subscriptionFeatureFlagger: subscriptionFeatureFlagger,
            pixelHandler: { type in
                XCTAssertEqual(type, .deadToken)
                expectation.fulfill()
            }
        )

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Error expected")
        } catch SubscriptionManagerError.tokenUnavailable {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await fulfillment(of: [expectation], timeout: 0.1)
    }

    // MARK: - Subscription Status Tests

    func testRefreshCachedSubscription_ActiveSubscription() {
        let expectation = self.expectation(description: "Active subscription callback")
        let activeSubscription = PrivacyProSubscription(
            productId: "testProduct",
            name: "Test Subscription",
            billingPeriod: .monthly,
            startedAt: Date(),
            expiresOrRenewsAt: Date().addingTimeInterval(30 * 24 * 60 * 60), // 30 days from now
            platform: .stripe,
            status: .autoRenewable
        )
        mockSubscriptionEndpointService.getSubscriptionResult = .success(activeSubscription)
        mockOAuthClient.getTokensResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        subscriptionManager.refreshCachedSubscription { isActive in
            XCTAssertTrue(isActive)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.1)
    }

    func testRefreshCachedSubscription_ExpiredSubscription() {
        let expectation = self.expectation(description: "Expired subscription callback")
        let expiredSubscription = PrivacyProSubscription(
            productId: "testProduct",
            name: "Test Subscription",
            billingPeriod: .monthly,
            startedAt: Date().addingTimeInterval(-30 * 24 * 60 * 60), // 30 days ago
            expiresOrRenewsAt: Date().addingTimeInterval(-1), // expired
            platform: .apple,
            status: .expired
        )
        mockSubscriptionEndpointService.getSubscriptionResult = .success(expiredSubscription)

        subscriptionManager.refreshCachedSubscription { isActive in
            XCTAssertFalse(isActive)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.1)
    }

    // MARK: - URL Generation Tests

    func testURLGeneration_ForCustomerPortal() async throws {
        mockOAuthClient.getTokensResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        let customerPortalURLString = "https://example.com/customer-portal"
        mockSubscriptionEndpointService.getCustomerPortalURLResult = .success(GetCustomerPortalURLResponse(customerPortalUrl: customerPortalURLString))

        let url = try await subscriptionManager.getCustomerPortalURL()
        XCTAssertEqual(url.absoluteString, customerPortalURLString)
    }

    func testURLGeneration_ForSubscriptionTypes() {
        let environment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)
        subscriptionManager = DefaultSubscriptionManager(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: environment,
            subscriptionFeatureFlagger: subscriptionFeatureFlagger,
            pixelHandler: { _ in }
        )

        let helpURL = subscriptionManager.url(for: .purchase)
        XCTAssertEqual(helpURL.absoluteString, "https://duckduckgo.com/subscriptions/welcome")
    }

    // MARK: - Purchase Confirmation Tests

    func testConfirmPurchase_ErrorHandling() async throws {
        let testSignature = "invalidSignature"
        mockSubscriptionEndpointService.confirmPurchaseResult = .failure(APIRequestV2.Error.invalidResponse)
        mockOAuthClient.getTokensResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        do {
            _ = try await subscriptionManager.confirmPurchase(signature: testSignature)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? APIRequestV2.Error, APIRequestV2.Error.invalidResponse)
        }
    }

    // MARK: - Tests for save and loadEnvironmentFrom

    var subscriptionEnvironment: SubscriptionEnvironment!

    func testLoadEnvironmentFromUserDefaults() async throws {
        subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production,
                                                          purchasePlatform: .appStore)
        let userDefaultsSuiteName = "SubscriptionManagerTests"
        // Given
        let userDefaults = UserDefaults(suiteName: userDefaultsSuiteName)!
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)

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

    // MARK: - Tests for url

    func testForProductionURL() throws {
        // Given
        let productionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)

        let productionSubscriptionManager = DefaultSubscriptionManager(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: productionEnvironment,
            subscriptionFeatureFlagger: subscriptionFeatureFlagger,
            pixelHandler: { _ in }
        )

        // When
        let productionPurchaseURL = productionSubscriptionManager.url(for: .purchase)

        // Then
        XCTAssertEqual(productionPurchaseURL, SubscriptionURL.purchase.subscriptionURL(environment: .production))
    }

    func testForStagingURL() throws {
        // Given
        let stagingEnvironment = SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .appStore)

        let stagingSubscriptionManager = DefaultSubscriptionManager(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: stagingEnvironment,
            subscriptionFeatureFlagger: subscriptionFeatureFlagger,
            pixelHandler: { _ in }
        )

        // When
        let stagingPurchaseURL = stagingSubscriptionManager.url(for: .purchase)

        // Then
        XCTAssertEqual(stagingPurchaseURL, SubscriptionURL.purchase.subscriptionURL(environment: .staging))
    }
}
