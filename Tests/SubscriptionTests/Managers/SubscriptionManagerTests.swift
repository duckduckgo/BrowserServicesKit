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
import NetworkingTestingUtils

class SubscriptionManagerTests: XCTestCase {

    var subscriptionManager: DefaultSubscriptionManagerV2!
    var mockOAuthClient: MockOAuthClient!
    var mockSubscriptionEndpointService: SubscriptionEndpointServiceMockV2!
    var mockStorePurchaseManager: StorePurchaseManagerMockV2!

    override func setUp() {
        super.setUp()

        mockOAuthClient = MockOAuthClient()
        mockSubscriptionEndpointService = SubscriptionEndpointServiceMockV2()
        mockStorePurchaseManager = StorePurchaseManagerMockV2()

        subscriptionManager = DefaultSubscriptionManagerV2(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .stripe),
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
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.refreshTokenExpired)
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
        subscriptionManager = DefaultSubscriptionManagerV2(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .stripe),
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

    func testRefreshCachedSubscription_ActiveSubscription() async {
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
        mockOAuthClient.isUserAuthenticated = true

        let subscription = try! await subscriptionManager.getSubscription(cachePolicy: .reloadIgnoringLocalCacheData)
        XCTAssertTrue(subscription.isActive)
    }

    func testRefreshCachedSubscription_ExpiredSubscription() async {
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

        do {
            try await subscriptionManager.getSubscription(cachePolicy: .reloadIgnoringLocalCacheData)
        } catch {
            XCTAssertEqual(error.localizedDescription, SubscriptionEndpointServiceError.noData.localizedDescription)
        }
    }

    // MARK: - URL Generation Tests

    func testURLGeneration_ForCustomerPortal() async throws {
        mockOAuthClient.isUserAuthenticated = true
        mockOAuthClient.getTokensResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        let customerPortalURLString = "https://example.com/customer-portal"
        mockSubscriptionEndpointService.getCustomerPortalURLResult = .success(GetCustomerPortalURLResponse(customerPortalUrl: customerPortalURLString))

        let url = try await subscriptionManager.getCustomerPortalURL()
        XCTAssertEqual(url.absoluteString, customerPortalURLString)
    }

    func testURLGeneration_ForSubscriptionTypes() {
        let environment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)
        subscriptionManager = DefaultSubscriptionManagerV2(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: environment,
            pixelHandler: { _ in }
        )

        let helpURL = subscriptionManager.url(for: .purchase)
        XCTAssertEqual(helpURL.absoluteString, "https://duckduckgo.com/subscriptions")
    }

    // MARK: - Purchase Confirmation Tests

    func testConfirmPurchase_ErrorHandling() async throws {
        let testSignature = "invalidSignature"
        mockSubscriptionEndpointService.confirmPurchaseResult = .failure(APIRequestV2.Error.invalidResponse)
        mockOAuthClient.getTokensResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        do {
            _ = try await subscriptionManager.confirmPurchase(signature: testSignature, additionalParams: nil)
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

        var loadedEnvironment = DefaultSubscriptionManagerV2.loadEnvironmentFrom(userDefaults: userDefaults)
        XCTAssertNil(loadedEnvironment)

        // When
        DefaultSubscriptionManagerV2.save(subscriptionEnvironment: subscriptionEnvironment,
                                        userDefaults: userDefaults)
        loadedEnvironment = DefaultSubscriptionManagerV2.loadEnvironmentFrom(userDefaults: userDefaults)

        // Then
        XCTAssertEqual(loadedEnvironment?.serviceEnvironment, subscriptionEnvironment.serviceEnvironment)
        XCTAssertEqual(loadedEnvironment?.purchasePlatform, subscriptionEnvironment.purchasePlatform)
    }

    // MARK: - Tests for url

    func testForProductionURL() throws {
        // Given
        let productionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)

        let productionSubscriptionManager = DefaultSubscriptionManagerV2(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: productionEnvironment,
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

        let stagingSubscriptionManager = DefaultSubscriptionManagerV2(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: stagingEnvironment,
            pixelHandler: { _ in }
        )

        // When
        let stagingPurchaseURL = stagingSubscriptionManager.url(for: .purchase)

        // Then
        XCTAssertEqual(stagingPurchaseURL, SubscriptionURL.purchase.subscriptionURL(environment: .staging))
    }
}
