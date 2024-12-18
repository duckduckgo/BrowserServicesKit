//
//  PrivacyProSubscriptionIntegrationTests.swift
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
import TestUtils
import SubscriptionTestingUtilities
import JWTKit

final class PrivacyProSubscriptionIntegrationTests: XCTestCase {

    var apiService: MockAPIService!
    var tokenStorage: MockTokenStorage!
    var legacyAccountStorage: MockLegacyTokenStorage!
    var subscriptionManager: DefaultSubscriptionManager!
    var appStorePurchaseFlow: DefaultAppStorePurchaseFlow!
    var appStoreRestoreFlow: DefaultAppStoreRestoreFlow!
    var stripePurchaseFlow: DefaultStripePurchaseFlow!
    var storePurchaseManager: StorePurchaseManagerMock!
    var subscriptionFeatureFlagger: FeatureFlaggerMapping<SubscriptionFeatureFlags>!

    let subscriptionSelectionID = "ios.subscription.1month"

    override func setUpWithError() throws {
        apiService = MockAPIService()
        apiService.authorizationRefresherCallback = { _ in
            return OAuthTokensFactory.makeValidTokenContainer().accessToken
        }
        let subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .appStore)
        let authService = DefaultOAuthService(baseURL: OAuthEnvironment.staging.url, apiService: apiService)
        // keychain storage
        tokenStorage = MockTokenStorage()
        legacyAccountStorage = MockLegacyTokenStorage()

        let authClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                            legacyTokenStorage: legacyAccountStorage,
                                            authService: authService)
        storePurchaseManager = StorePurchaseManagerMock()
        let subscriptionEndpointService = DefaultSubscriptionEndpointService(apiService: apiService,
                                                                             baseURL: subscriptionEnvironment.serviceEnvironment.url)
        let pixelHandler: SubscriptionManager.PixelHandler = { type in
            print("Pixel fired: \(type)")
        }
        subscriptionFeatureFlagger = FeatureFlaggerMapping<SubscriptionFeatureFlags>(mapping: { $0.defaultState })

        subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                         oAuthClient: authClient,
                                                         subscriptionEndpointService: subscriptionEndpointService,
                                                         subscriptionEnvironment: subscriptionEnvironment,
                                                         subscriptionFeatureFlagger: subscriptionFeatureFlagger,
                                                         pixelHandler: pixelHandler)

        appStoreRestoreFlow = DefaultAppStoreRestoreFlow(subscriptionManager: subscriptionManager,
                                                         storePurchaseManager: storePurchaseManager)
        appStorePurchaseFlow = DefaultAppStorePurchaseFlow(subscriptionManager: subscriptionManager,
                                                           storePurchaseManager: storePurchaseManager,
                                                           appStoreRestoreFlow: appStoreRestoreFlow)
        stripePurchaseFlow = DefaultStripePurchaseFlow(subscriptionManager: subscriptionManager)
    }

    override func tearDownWithError() throws {
        apiService = nil
        tokenStorage = nil
        legacyAccountStorage = nil
        subscriptionManager = nil
        appStorePurchaseFlow = nil
        appStoreRestoreFlow = nil
        stripePurchaseFlow = nil
    }

    // MARK: - Apple store

    func testAppStorePurchaseSuccess() async throws {

        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetAccessTokenResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetJWKS(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockConfirmPurchase(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetProducts(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetFeatures(destinationMockAPIService: apiService, success: true, subscriptionID: "ios.subscription.1month")

        (subscriptionManager.oAuthClient as! DefaultOAuthClient).testingDecodedTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()

        // configure mock store purchase manager responses
        storePurchaseManager.purchaseSubscriptionResult = .success("purchaseTransactionJWS")

        // Buy subscription

        var purchaseTransactionJWS: String?
        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID) {
        case .success(let transactionJWS):
            purchaseTransactionJWS = transactionJWS
        case .failure(let error):
            XCTFail("Purchase failed with error: \(error)")
        }
        XCTAssertNotNil(purchaseTransactionJWS)

        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: purchaseTransactionJWS!) {
        case .success:
            break
        case .failure(let error):
            XCTFail("Purchase failed with error: \(error)")
        }
    }

    func testAppStorePurchaseFailure_authorise() async throws {
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: false)

        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .internalError(let innerError):
                XCTAssertEqual(innerError as? SubscriptionManagerError, .tokenUnavailable(error: OAuthServiceError.authAPIError(code: .invalidAuthorizationRequest)))
            default:
                XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testAppStorePurchaseFailure_create_account() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: false)

        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .internalError(let innerError):
                XCTAssertEqual(innerError as? SubscriptionManagerError, .tokenUnavailable(error: OAuthServiceError.authAPIError(code: .invalidAuthorizationRequest)))
            default:
                XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testAppStorePurchaseFailure_get_token() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetAccessTokenResponse(destinationMockAPIService: apiService, success: false)

        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .internalError(let innerError):
                XCTAssertEqual(innerError as? SubscriptionManagerError, .tokenUnavailable(error: OAuthServiceError.authAPIError(code: .invalidAuthorizationRequest)))
            default:
                XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testAppStorePurchaseFailure_get_JWKS() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetAccessTokenResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetJWKS(destinationMockAPIService: apiService, success: false)

        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .internalError(let innerError):
                XCTAssertEqual(innerError as? SubscriptionManagerError, .tokenUnavailable(error: OAuthServiceError.invalidResponseCode(.badRequest)))
            default:
                XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testAppStorePurchaseFailure_confirm_purchase() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetAccessTokenResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetJWKS(destinationMockAPIService: apiService, success: true)

        (subscriptionManager.oAuthClient as! DefaultOAuthClient).testingDecodedTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        storePurchaseManager.purchaseSubscriptionResult = .success("purchaseTransactionJWS")

        APIMockResponseFactory.mockConfirmPurchase(destinationMockAPIService: apiService, success: false)

        var purchaseTransactionJWS: String?
        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID) {
        case .success(let transactionJWS):
            purchaseTransactionJWS = transactionJWS
        case .failure(let error):
            XCTFail("Purchase failed with error: \(error)")
        }
        XCTAssertNotNil(purchaseTransactionJWS)

        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: purchaseTransactionJWS!) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertEqual(error, .purchaseFailed(SubscriptionEndpointServiceError.invalidResponseCode(.badRequest)))
        }
    }

    func testAppStorePurchaseFailure_get_features() async throws {
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetAccessTokenResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetJWKS(destinationMockAPIService: apiService, success: true)

        (subscriptionManager.oAuthClient as! DefaultOAuthClient).testingDecodedTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        storePurchaseManager.purchaseSubscriptionResult = .success("purchaseTransactionJWS")

        APIMockResponseFactory.mockConfirmPurchase(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetFeatures(destinationMockAPIService: apiService, success: false, subscriptionID: "ios.subscription.1month")

        (subscriptionManager.oAuthClient as! DefaultOAuthClient).testingDecodedTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()

        var purchaseTransactionJWS: String?
        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID) {
        case .success(let transactionJWS):
            purchaseTransactionJWS = transactionJWS
        case .failure(let error):
            XCTFail("Purchase failed with error: \(error)")
        }
        XCTAssertNotNil(purchaseTransactionJWS)

        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: purchaseTransactionJWS!) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertEqual(error, .purchaseFailed(SubscriptionEndpointServiceError.invalidResponseCode(.badRequest)))
        }
    }

    // MARK: - Stripe

    func testStripePurchaseSuccess() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetAccessTokenResponse(destinationMockAPIService: apiService, success: true)

        (subscriptionManager.oAuthClient as! DefaultOAuthClient).testingDecodedTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()

        // Buy subscription
        let email = "test@duck.com"
        let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: email)
        switch result {
        case .success(let success):
            XCTAssertNotNil(success.type)
            XCTAssertNotNil(success.token)
        case .failure(let error):
            XCTFail("Purchase failed with error: \(error)")
        }
    }

    func testStripePurchaseFailure_authorise() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: false)
        (subscriptionManager.oAuthClient as! DefaultOAuthClient).testingDecodedTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()

        // Buy subscription
        let email = "test@duck.com"
        let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: email)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertEqual(error, StripePurchaseFlowError.accountCreationFailed)
        }
    }

    func testStripePurchaseFailure_create_account() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: false)

        (subscriptionManager.oAuthClient as! DefaultOAuthClient).testingDecodedTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()

        // Buy subscription
        let email = "test@duck.com"
        let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: email)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertEqual(error, StripePurchaseFlowError.accountCreationFailed)
        }
    }

    func testStripePurchaseFailure_get_token() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetAccessTokenResponse(destinationMockAPIService: apiService, success: false)

        (subscriptionManager.oAuthClient as! DefaultOAuthClient).testingDecodedTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()

        // Buy subscription
        let email = "test@duck.com"
        let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: email)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertEqual(error, StripePurchaseFlowError.accountCreationFailed)
        }
    }
}
