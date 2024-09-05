//
//  StripePurchaseFlowTests.swift
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

final class StripePurchaseFlowTests: XCTestCase {

    private struct Constants {
        static let authToken = UUID().uuidString
        static let accessToken = UUID().uuidString
        static let externalID = UUID().uuidString

        static let unknownServerError = APIServiceError.serverError(statusCode: 401, error: "unknown_error")
    }

    var accountManager: AccountManagerMock!
    var subscriptionService: SubscriptionEndpointServiceMock!
    var authEndpointService: AuthEndpointServiceMock!

    var stripePurchaseFlow: StripePurchaseFlow!

    override func setUpWithError() throws {
        accountManager = AccountManagerMock()
        subscriptionService = SubscriptionEndpointServiceMock()
        authEndpointService = AuthEndpointServiceMock()

        stripePurchaseFlow = DefaultStripePurchaseFlow(subscriptionEndpointService: subscriptionService,
                                                       authEndpointService: authEndpointService,
                                                       accountManager: accountManager)
    }

    override func tearDownWithError() throws {
        accountManager = nil
        subscriptionService = nil
        authEndpointService = nil

        stripePurchaseFlow = nil
    }

    // MARK: - Tests for subscriptionOptions

    func testSubscriptionOptionsSuccess() async throws {
        subscriptionService .getProductsResult = .success(SubscriptionMockFactory.productsItems)

        let result = await stripePurchaseFlow.subscriptionOptions()
        switch result {
        case .success(let success):
            XCTAssertEqual(success.platform, SubscriptionPlatformName.stripe.rawValue)
            XCTAssertEqual(success.options.count, SubscriptionMockFactory.productsItems.count)
            XCTAssertEqual(success.features.count, SubscriptionFeatureName.allCases.count)
            let allNames = success.features.compactMap({ feature in feature.name})
            for name in SubscriptionFeatureName.allCases {
                XCTAssertTrue(allNames.contains(name.rawValue))
            }
        case .failure(let failure):
            XCTFail("Unexpected failure: \(failure)")
        }
    }

    func testSubscriptionOptionsErrorWhenNoProductsAreFetched() async throws {
        subscriptionService.getProductsResult = .failure(.unknownServerError)

        let result = await stripePurchaseFlow.subscriptionOptions()
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let failure):
            XCTAssertEqual(failure, .noProductsFound)
        }
    }

    // MARK: - Tests for prepareSubscriptionPurchase

    func testPrepareSubscriptionPurchaseSuccessWhenSignedInAndSubscriptionExpired() async throws {
        let subscription = SubscriptionMockFactory.expiredSubscription

        accountManager.accessToken = Constants.accessToken

        let subscriptionServiceSignOutExpectation = expectation(description: "signOut()")
        subscriptionService.onSignOut = { subscriptionServiceSignOutExpectation.fulfill() }
        subscriptionService.getSubscriptionResult = .success(subscription)
        subscriptionService.getProductsResult = .success(SubscriptionMockFactory.productsItems)
        

        XCTAssertTrue(accountManager.isUserAuthenticated)
        XCTAssertFalse(subscription.isActive)

        let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: nil)
        switch result {
        case .success(let success):
            await fulfillment(of: [subscriptionServiceSignOutExpectation], timeout: 0.1)
            XCTAssertEqual(success.type, "redirect")
            XCTAssertEqual(success.token, Constants.accessToken)
        case .failure(let failure):
            XCTFail("Unexpected failure: \(failure)")
        }
    }

    func testPrepareSubscriptionPurchaseSuccessWhenNotSignedIn() async throws {
        authEndpointService.createAccountResult = .success(CreateAccountResponse(authToken: Constants.authToken,
                                                                                 externalID: Constants.externalID,
                                                                                 status: "created"))
        XCTAssertFalse(accountManager.isUserAuthenticated)

        let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: nil)
        switch result {
        case .success(let success):
            XCTAssertEqual(success.type, "redirect")
            XCTAssertEqual(success.token, Constants.authToken)
            XCTAssertEqual(accountManager.authToken, Constants.authToken)
        case .failure(let failure):
            XCTFail("Unexpected failure: \(failure)")
        }
    }

    func testPrepareSubscriptionPurchaseErrorWhenAccountCreationFailed() async throws {
        authEndpointService.createAccountResult = .failure(Constants.unknownServerError)
        XCTAssertNil(accountManager.accessToken)

        let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: nil)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let failure):
            XCTAssertEqual(failure, .accountCreationFailed)
        }
    }

    func testPrepareSubscriptionPurchaseErrorWhenWhenSignedInAndSubscriptionActive() async throws {
        // TODO: prepareSubscriptionPurchase should fail when has active subscription
    }

    // MARK: - Tests for completeSubscriptionPurchase

    func testCompleteSubscriptionPurchaseSuccessOnInitialPurchase() async throws {
        // Initial purchase flow: authToken is present but no accessToken yet
        accountManager.authToken = Constants.authToken
        XCTAssertNil(accountManager.accessToken)

        let subscriptionServiceSignOutExpectation = expectation(description: "signOut")
        subscriptionService.onSignOut = { subscriptionServiceSignOutExpectation.fulfill() }

        accountManager.exchangeAuthTokenToAccessTokenResult = .success(Constants.accessToken)
        accountManager.onExchangeAuthTokenToAccessToken = { authToken in
            XCTAssertEqual(authToken, Constants.authToken)
        }


        let accountManagerFetchAccountDetailsExpectation = expectation(description: "fetchAccountDetails")
        accountManager.onFetchAccountDetails = { accessToken in
            accountManagerFetchAccountDetailsExpectation.fulfill()
            XCTAssertEqual(accessToken, Constants.accessToken)
            return .success(AccountManager.AccountDetails(email: nil, externalID: Constants.externalID))
        }

        let accountManagerStoreAuthTokenExpectation = expectation(description: "storeAuthToken")
        accountManager.onStoreAuthToken = { authToken in
            accountManagerStoreAuthTokenExpectation.fulfill()
            XCTAssertEqual(authToken, Constants.authToken)
        }

        let accountManagerStoreAccountExpectation = expectation(description: "storeAccount")
        accountManager.onStoreAccount = { accessToken, email, externalID in
            accountManagerStoreAccountExpectation.fulfill()
            XCTAssertEqual(accessToken, Constants.accessToken)
            XCTAssertEqual(externalID, Constants.externalID)
        }

        let accountManagerCheckForEntitlementsExpectation = expectation(description: "checkForEntitlements")
        accountManager.onCheckForEntitlements = { wait, retry in
            accountManagerCheckForEntitlementsExpectation.fulfill()
            XCTAssertEqual(wait, 2.0)
            XCTAssertEqual(retry, 5)
            return true
        }

        XCTAssertFalse(accountManager.isUserAuthenticated)
        XCTAssertNotNil(accountManager.authToken)

        await stripePurchaseFlow.completeSubscriptionPurchase()

        await fulfillment(of: [subscriptionServiceSignOutExpectation,
                               accountManagerFetchAccountDetailsExpectation,
                               accountManagerStoreAuthTokenExpectation,
                               accountManagerStoreAccountExpectation,
                               accountManagerCheckForEntitlementsExpectation], timeout: 0.1)
        XCTAssertTrue(accountManager.exchangeAuthTokenToAccessTokenCalled)
        XCTAssertTrue(accountManager.isUserAuthenticated)
        XCTAssertEqual(accountManager.accessToken, Constants.accessToken)
        XCTAssertEqual(accountManager.externalID, Constants.externalID)
    }

    func testCompleteSubscriptionPurchaseSuccessOnRepurchase() async throws {
        // Repurchase flow: authToken, accessToken and externalID are present
        accountManager.authToken = Constants.authToken
        accountManager.accessToken = Constants.accessToken
        accountManager.externalID = Constants.externalID

        let subscriptionServiceSignOutExpectation = expectation(description: "signOut")
        subscriptionService.onSignOut = { subscriptionServiceSignOutExpectation.fulfill() }

        let fetchAccountDetailsExpectation = expectation(description: "fetchAccountDetails")
        fetchAccountDetailsExpectation.isInverted = true
        accountManager.onFetchAccountDetails = { _ in
            fetchAccountDetailsExpectation.fulfill()
            return .success(AccountManager.AccountDetails(email: nil, externalID: Constants.externalID))
        }

        let storeAuthTokenExpectation = expectation(description: "storeAuthToken")
        storeAuthTokenExpectation.isInverted = true
        accountManager.onStoreAuthToken = { authToken in
            storeAuthTokenExpectation.fulfill()
        }

        let storeAccountExpectation = expectation(description: "storeAccount")
        storeAccountExpectation.isInverted = true
        accountManager.onStoreAccount = { _, _, _ in
            storeAccountExpectation.fulfill()
        }

        let checkForEntitlementsExpectation = expectation(description: "checkForEntitlements")
        accountManager.onCheckForEntitlements = { wait, retry in
            checkForEntitlementsExpectation.fulfill()
            XCTAssertEqual(wait, 2.0)
            XCTAssertEqual(retry, 5)
            return true
        }

        XCTAssertTrue(accountManager.isUserAuthenticated)

        await stripePurchaseFlow.completeSubscriptionPurchase()

        await fulfillment(of: [subscriptionServiceSignOutExpectation,
                               fetchAccountDetailsExpectation,
                               storeAuthTokenExpectation,
                               storeAccountExpectation,
                               checkForEntitlementsExpectation], timeout: 0.1)
        XCTAssertFalse(accountManager.exchangeAuthTokenToAccessTokenCalled)
        XCTAssertTrue(accountManager.isUserAuthenticated)
        XCTAssertEqual(accountManager.accessToken, Constants.accessToken)
        XCTAssertEqual(accountManager.externalID, Constants.externalID)
    }
}
