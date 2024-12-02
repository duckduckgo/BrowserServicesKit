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

final class PrivacyProSubscriptionIntegrationTests: XCTestCase {

    var apiService: MockAPIService!
    var tokenStorage: MockTokenStorage!
    var legacyAccountStorage: MockLegacyTokenStorage!
    var subscriptionManager: DefaultSubscriptionManager!
    var appStorePurchaseFlow: DefaultAppStorePurchaseFlow!
    var appStoreRestoreFlow: DefaultAppStoreRestoreFlow!
    var storePurchaseManager: StorePurchaseManagerMock!
    var subscriptionFeatureMappingCache: SubscriptionFeatureMappingCacheMock!
    var subscriptionFeatureFlagger: FeatureFlaggerMapping<SubscriptionFeatureFlags>!

    let subscriptionSelectionID = "ios.subscription.1month"

    override func setUpWithError() throws {

        let subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .appStore)
        apiService = MockAPIService()
        let authService = DefaultOAuthService(baseURL: OAuthEnvironment.staging.url, apiService: apiService)

        // keychain storage
        tokenStorage = MockTokenStorage()
        legacyAccountStorage = MockLegacyTokenStorage()

        let authClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                            legacyTokenStorage: legacyAccountStorage,
                                            authService: authService)
        apiService.authorizationRefresherCallback = { _ in
            return OAuthTokensFactory.makeValidTokenContainer().accessToken
        }
        storePurchaseManager = StorePurchaseManagerMock()
        let subscriptionEndpointService = DefaultSubscriptionEndpointService(apiService: apiService,
                                                                             baseURL: subscriptionEnvironment.serviceEnvironment.url)
        let pixelHandler: SubscriptionManager.PixelHandler = { type in
            print("Pixel fired: \(type)")
        }
        subscriptionFeatureMappingCache = SubscriptionFeatureMappingCacheMock()
        subscriptionFeatureFlagger = FeatureFlaggerMapping<SubscriptionFeatureFlags>(mapping: { $0.defaultState })

        subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                         oAuthClient: authClient,
                                                         subscriptionEndpointService: subscriptionEndpointService,
                                                         subscriptionFeatureMappingCache: subscriptionFeatureMappingCache,
                                                         subscriptionEnvironment: subscriptionEnvironment,
                                                         subscriptionFeatureFlagger: subscriptionFeatureFlagger,
                                                         pixelHandler: pixelHandler)

        appStoreRestoreFlow = DefaultAppStoreRestoreFlow(subscriptionManager: subscriptionManager,
                                                         storePurchaseManager: storePurchaseManager)

        appStorePurchaseFlow = DefaultAppStorePurchaseFlow(subscriptionManager: subscriptionManager,
                                                           storePurchaseManager: storePurchaseManager,
                                                           appStoreRestoreFlow: appStoreRestoreFlow)
    }

    override func tearDownWithError() throws {
        apiService = nil
        tokenStorage = nil
        legacyAccountStorage = nil
        subscriptionManager = nil
        appStorePurchaseFlow = nil
        appStoreRestoreFlow = nil
    }

    func testPurchaseSuccess() async throws {

        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetAccessTokenResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetJWKS(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockConfirmPurchase(destinationMockAPIService: apiService, success: true)

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
}
