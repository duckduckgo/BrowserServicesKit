//
//  AppStorePurchaseFlowTests.swift
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

final class AppStorePurchaseFlowTests: XCTestCase {

    private struct Constants {
        static let authToken = UUID().uuidString
        static let accessToken = UUID().uuidString
        static let externalID = UUID().uuidString

        static let productID = UUID().uuidString
        static let transactionJWS = "dGhpcyBpcyBub3QgYSByZWFsIEFw(...)cCBTdG9yZSB0cmFuc2FjdGlvbiBKV1M="

        static let createAccountResponse = CreateAccountResponse(authToken: authToken,
                                                                 externalID: externalID,
                                                                 status: "ok")

        static let restoredAccount = RestoredAccountDetails(authToken: authToken,
                                                            accessToken: accessToken, 
                                                            externalID: externalID,
                                                            email: nil)

        static let account = ValidateTokenResponse.Account(email: nil,
                                                           entitlements: [],
                                                           externalID: externalID)

        static let unknownServerError = APIServiceError.serverError(statusCode: 401, error: "unknown_error")
    }

    var accountManager: AccountManagerMock!
    var subscriptionService: SubscriptionEndpointServiceMock!
    var authService: AuthEndpointServiceMock!
    var storePurchaseManager: StorePurchaseManagerMock!

    var appStoreRestoreFlow: AppStoreRestoreFlowMock!

    var appStorePurchaseFlow: AppStorePurchaseFlow!

    override func setUpWithError() throws {
        subscriptionService = SubscriptionEndpointServiceMock()
        storePurchaseManager = StorePurchaseManagerMock()
        accountManager = AccountManagerMock()
        appStoreRestoreFlow = AppStoreRestoreFlowMock()
        authService = AuthEndpointServiceMock()

        appStorePurchaseFlow = DefaultAppStorePurchaseFlow(subscriptionEndpointService: subscriptionService,
                                                           storePurchaseManager: storePurchaseManager,
                                                           accountManager: accountManager,
                                                           appStoreRestoreFlow: appStoreRestoreFlow,
                                                           authEndpointService: authService)
    }

    override func tearDownWithError() throws {
        subscriptionService = nil
        storePurchaseManager = nil
        accountManager = nil
        appStoreRestoreFlow = nil
        authService = nil

        appStorePurchaseFlow = nil
    }

    // MARK: - Tests for purchaseSubscription

    func testPurchaseSubscriptionSuccess() async throws {
        XCTAssertFalse(accountManager.isUserAuthenticated)

        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.missingAccountOrTransactions)
        authService.createAccountResult = .success(Constants.createAccountResponse)
        accountManager.exchangeAuthTokenToAccessTokenResult = .success(Constants.accessToken)
        accountManager.onFetchAccountDetails = { _ in .success((email: "", externalID: Constants.externalID)) }
        storePurchaseManager.purchaseSubscriptionResult = .success(Constants.transactionJWS)

        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success(let success):
            XCTAssertTrue(appStoreRestoreFlow.restoreAccountFromPastPurchaseCalled)
            XCTAssertTrue(authService.createAccountCalled)
            XCTAssertTrue(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertTrue(accountManager.storeAuthTokenCalled)
            XCTAssertTrue(accountManager.storeAccountCalled)
            XCTAssertTrue(storePurchaseManager.purchaseSubscriptionCalled)
            XCTAssertEqual(success, Constants.transactionJWS)
        case .failure(let error):
            XCTFail("Unexpected failure: \(String(reflecting: error))")
        }
    }

    func testPurchaseSubscriptionSuccessRepurchaseForAppStoreSubscription() async throws {
        accountManager.authToken = Constants.authToken
        accountManager.accessToken = Constants.accessToken
        accountManager.externalID = Constants.externalID

        let subscription = SubscriptionMockFactory.expiredSubscription

        XCTAssertFalse(subscription.isActive)
        XCTAssertEqual(subscription.platform, .apple)
        XCTAssertTrue(accountManager.isUserAuthenticated)

        subscriptionService.getSubscriptionResult = .success(subscription)
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.subscriptionExpired(accountDetails: Constants.restoredAccount))
        storePurchaseManager.purchaseSubscriptionResult = .success(Constants.transactionJWS)

        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success(let success):
            XCTAssertTrue(appStoreRestoreFlow.restoreAccountFromPastPurchaseCalled)
            XCTAssertFalse(authService.createAccountCalled)
            XCTAssertFalse(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertTrue(storePurchaseManager.purchaseSubscriptionCalled)
            XCTAssertEqual(success, Constants.transactionJWS)
            XCTAssertEqual(accountManager.externalID, Constants.externalID)
        case .failure(let error):
            XCTFail("Unexpected failure: \(String(reflecting: error))")
        }
    }

    func testPurchaseSubscriptionSuccessRepurchaseForNonAppStoreSubscription() async throws {
        accountManager.authToken = Constants.authToken
        accountManager.accessToken = Constants.accessToken
        accountManager.externalID = Constants.externalID

        let subscription = SubscriptionMockFactory.expiredStripeSubscription

        XCTAssertFalse(subscription.isActive)
        XCTAssertNotEqual(subscription.platform, .apple)
        XCTAssertTrue(accountManager.isUserAuthenticated)

        subscriptionService.getSubscriptionResult = .success(subscription)
        storePurchaseManager.purchaseSubscriptionResult = .success(Constants.transactionJWS)

        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success:
            XCTAssertFalse(appStoreRestoreFlow.restoreAccountFromPastPurchaseCalled)
            XCTAssertFalse(authService.createAccountCalled)
            XCTAssertEqual(accountManager.externalID, Constants.externalID)
        case .failure(let error):
            XCTFail("Unexpected failure: \(String(reflecting: error))")
        }
    }

    func testPurchaseSubscriptionErrorWhenActiveSubscriptionRestoredFromAppStore() async throws {
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .success(Void())

        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertFalse(authService.createAccountCalled)
            XCTAssertFalse(storePurchaseManager.purchaseSubscriptionCalled)
            XCTAssertEqual(error, .activeSubscriptionAlreadyPresent)
        }
    }

    func testPurchaseSubscriptionErrorWhenAccountCreationFails() async throws {
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.missingAccountOrTransactions)
        authService.createAccountResult = .failure(.unknownServerError)
        
        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertTrue(authService.createAccountCalled)
            XCTAssertFalse(storePurchaseManager.purchaseSubscriptionCalled)
            XCTAssertEqual(error, .accountCreationFailed)
        }
    }

    func testPurchaseSubscriptionErrorWhenAppStorePurchaseFails() async throws {
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.missingAccountOrTransactions)
        authService.createAccountResult = .success(Constants.createAccountResponse)
        accountManager.exchangeAuthTokenToAccessTokenResult = .success(Constants.accessToken)
        accountManager.onFetchAccountDetails = { _ in .success((email: "", externalID: Constants.externalID)) }
        storePurchaseManager.purchaseSubscriptionResult = .failure(.productNotFound)

        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertTrue(authService.createAccountCalled)
            XCTAssertTrue(storePurchaseManager.purchaseSubscriptionCalled)
            XCTAssertEqual(error, .purchaseFailed)
        }
    }

    func testPurchaseSubscriptionErrorWhenAppStorePurchaseCancelledByUser() async throws {
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.missingAccountOrTransactions)
        authService.createAccountResult = .success(Constants.createAccountResponse)
        accountManager.exchangeAuthTokenToAccessTokenResult = .success(Constants.accessToken)
        accountManager.onFetchAccountDetails = { _ in .success((email: "", externalID: Constants.externalID)) }
        storePurchaseManager.purchaseSubscriptionResult = .failure(.purchaseCancelledByUser)

        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertTrue(authService.createAccountCalled)
            XCTAssertTrue(storePurchaseManager.purchaseSubscriptionCalled)
            XCTAssertEqual(error, .cancelledByUser)
        }
    }

    // MARK: - Tests for completeSubscriptionPurchase

    func testCompleteSubscriptionPurchaseSuccess() async throws {
        accountManager.accessToken = Constants.accessToken
        subscriptionService.confirmPurchaseResult = .success(ConfirmPurchaseResponse(email: nil,
                                                                                     entitlements: [],
                                                                                     subscription: SubscriptionMockFactory.subscription))

        subscriptionService.onUpdateCache = { subscription in
            XCTAssertEqual(subscription, SubscriptionMockFactory.subscription)
        }

        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: Constants.transactionJWS) {
        case .success(let success):
            XCTAssertTrue(subscriptionService.updateCacheWithSubscriptionCalled)
            XCTAssertTrue(accountManager.updateCacheWithEntitlementsCalled)
            XCTAssertEqual(success.type, "completed")
        case .failure(let error):
            XCTFail("Unexpected failure: \(String(reflecting: error))")
        }
    }

    func testCompleteSubscriptionPurchaseErrorDueToMissingAccessToken() async throws {
        XCTAssertNil(accountManager.accessToken)

        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: Constants.transactionJWS) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertEqual(error, .missingEntitlements)
        }
    }

    func testCompleteSubscriptionPurchaseErrorDueToFailedPurchaseConfirmation() async throws {
        accountManager.accessToken = Constants.accessToken
        subscriptionService.confirmPurchaseResult = .failure(Constants.unknownServerError)

        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: Constants.transactionJWS) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertEqual(error, .missingEntitlements)
        }
    }
}
