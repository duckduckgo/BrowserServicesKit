//
//  AppStoreRestoreFlowTests.swift
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

final class AppStoreRestoreFlowTests: XCTestCase {

    private struct Constants {
        static let authToken = UUID().uuidString
        static let accessToken = UUID().uuidString
        static let externalID = UUID().uuidString

        static let mostRecentTransactionJWS = "dGhpcyBpcyBub3QgYSByZWFsIEFw(...)cCBTdG9yZSB0cmFuc2FjdGlvbiBKV1M="
        static let storeLoginResponse = StoreLoginResponse(authToken: Constants.authToken,
                                                           email: "",
                                                           externalID: Constants.externalID,
                                                           id: 1,
                                                           status: "ok")

        static let unknownServerError = APIServiceError.serverError(statusCode: 401, error: "unknown_error")
    }

    var accountManager: AccountManagerMock!
    var subscriptionService: SubscriptionEndpointServiceMock!
    var authService: AuthEndpointServiceMock!
    var storePurchaseManager: StorePurchaseManagerMock!

    var appStoreRestoreFlow: AppStoreRestoreFlow!

    override func setUpWithError() throws {
        accountManager = AccountManagerMock()
        subscriptionService = SubscriptionEndpointServiceMock()
        authService = AuthEndpointServiceMock()
        storePurchaseManager = StorePurchaseManagerMock()
    }

    override func tearDownWithError() throws {
        accountManager = nil
        subscriptionService = nil
        authService = nil
        storePurchaseManager = nil

        appStoreRestoreFlow = nil
    }

    // MARK: - Tests for restoreAccountFromPastPurchase

    func testRestoreAccountFromPastPurchaseSuccess() async throws {
        storePurchaseManager.onMostRecentTransaction = {
            return Constants.mostRecentTransactionJWS
        }

        authService.storeLoginResult = .success(Constants.storeLoginResponse)

        accountManager.onExchangeAuthTokenToAccessToken = { _ in
            return .success(Constants.accessToken)
        }

        accountManager.onFetchAccountDetails = { accessToken in
            XCTAssertEqual(accessToken, Constants.accessToken)
            return .success(AccountManager.AccountDetails(email: nil, externalID: Constants.externalID))
        }

        let subscription = SubscriptionMockFactory.subscription
        subscriptionService.getSubscriptionResult = .success(subscription)

        XCTAssertTrue(subscription.isActive)

        accountManager.onStoreAuthToken = { authToken in
            XCTAssertEqual(authToken, Constants.authToken)
        }

        accountManager.onStoreAccount = { accessToken, email, externalID in
            XCTAssertEqual(accessToken, Constants.accessToken)
            XCTAssertEqual(externalID, Constants.externalID)
        }

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: accountManager,
                                              storePurchaseManager: storePurchaseManager,
                                              subscriptionEndpointService: subscriptionService,
                                              authEndpointService: authService)
        switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
        case .success:
            XCTAssertTrue(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertTrue(accountManager.fetchAccountDetailsCalled)
            XCTAssertTrue(accountManager.storeAuthTokenCalled)
            XCTAssertTrue(accountManager.storeAccountCalled)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testRestoreAccountFromPastPurchaseErrorDueToSubscriptionBeingExpired() async throws {
        storePurchaseManager.onMostRecentTransaction = {
            return Constants.mostRecentTransactionJWS
        }

        authService.storeLoginResult = .success(Constants.storeLoginResponse)

        accountManager.onExchangeAuthTokenToAccessToken = { _ in
            return .success(Constants.accessToken)
        }

        accountManager.onFetchAccountDetails = { accessToken in
            XCTAssertEqual(accessToken, Constants.accessToken)
            return .success(AccountManager.AccountDetails(email: nil, externalID: Constants.externalID))
        }

        let subscription = SubscriptionMockFactory.expiredSubscription
        subscriptionService.getSubscriptionResult = .success(subscription)

        XCTAssertFalse(subscription.isActive)

        accountManager.onStoreAuthToken = { authToken in
            XCTAssertEqual(authToken, Constants.authToken)
        }

        accountManager.onStoreAccount = { accessToken, email, externalID in
            XCTAssertEqual(accessToken, Constants.accessToken)
            XCTAssertEqual(externalID, Constants.externalID)
        }

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: accountManager,
                                              storePurchaseManager: storePurchaseManager,
                                              subscriptionEndpointService: subscriptionService,
                                              authEndpointService: authService)
        switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertTrue(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertTrue(accountManager.fetchAccountDetailsCalled)
            XCTAssertFalse(accountManager.storeAuthTokenCalled)
            XCTAssertFalse(accountManager.storeAccountCalled)

            guard case .subscriptionExpired(let accountDetails) = error else {
                XCTFail("Expected .subscriptionExpired error")
                return
            }

            XCTAssertEqual(accountDetails.authToken, Constants.authToken)
            XCTAssertEqual(accountDetails.accessToken, Constants.accessToken)
            XCTAssertEqual(accountDetails.externalID, Constants.externalID)
        }
    }

    func testRestoreAccountFromPastPurchaseErrorWhenNoRecentTransaction() async throws {
        storePurchaseManager.onMostRecentTransaction = { return nil }

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: accountManager,
                                              storePurchaseManager: storePurchaseManager,
                                              subscriptionEndpointService: subscriptionService,
                                              authEndpointService: authService)
        switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertFalse(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertFalse(accountManager.fetchAccountDetailsCalled)
            XCTAssertFalse(accountManager.storeAuthTokenCalled)
            XCTAssertFalse(accountManager.storeAccountCalled)
            XCTAssertEqual(error, .missingAccountOrTransactions)
        }
    }

    func testRestoreAccountFromPastPurchaseErrorDueToStoreLoginFailure() async throws {
        storePurchaseManager.onMostRecentTransaction = {
            return Constants.mostRecentTransactionJWS
        }

        authService.storeLoginResult = .failure(Constants.unknownServerError)

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: accountManager,
                                              storePurchaseManager: storePurchaseManager,
                                              subscriptionEndpointService: subscriptionService,
                                              authEndpointService: authService)
        switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertFalse(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertFalse(accountManager.fetchAccountDetailsCalled)
            XCTAssertFalse(accountManager.storeAuthTokenCalled)
            XCTAssertFalse(accountManager.storeAccountCalled)
            XCTAssertEqual(error, .pastTransactionAuthenticationError)
        }
    }

    func testRestoreAccountFromPastPurchaseErrorDueToStoreAuthTokenExchangeFailure() async throws {
        storePurchaseManager.onMostRecentTransaction = {
            return Constants.mostRecentTransactionJWS
        }

        authService.storeLoginResult = .success(Constants.storeLoginResponse)

        accountManager.onExchangeAuthTokenToAccessToken = { _ in
            return .failure(Constants.unknownServerError)
        }

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: accountManager,
                                              storePurchaseManager: storePurchaseManager,
                                              subscriptionEndpointService: subscriptionService,
                                              authEndpointService: authService)
        switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertTrue(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertFalse(accountManager.fetchAccountDetailsCalled)
            XCTAssertFalse(accountManager.storeAuthTokenCalled)
            XCTAssertFalse(accountManager.storeAccountCalled)
            XCTAssertEqual(error, .failedToObtainAccessToken)
        }
    }

    func testRestoreAccountFromPastPurchaseErrorDueToAccountDetailsFetchFailure() async throws {
        storePurchaseManager.onMostRecentTransaction = {
            return Constants.mostRecentTransactionJWS
        }

        authService.storeLoginResult = .success(Constants.storeLoginResponse)

        accountManager.onExchangeAuthTokenToAccessToken = { _ in
            return .success(Constants.accessToken)
        }

        accountManager.onFetchAccountDetails = { accessToken in
            XCTAssertEqual(accessToken, Constants.accessToken)
            return .failure(Constants.unknownServerError)
        }

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: accountManager,
                                              storePurchaseManager: storePurchaseManager,
                                              subscriptionEndpointService: subscriptionService,
                                              authEndpointService: authService)
        switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertTrue(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertTrue(accountManager.fetchAccountDetailsCalled)
            XCTAssertFalse(accountManager.storeAuthTokenCalled)
            XCTAssertFalse(accountManager.storeAccountCalled)
            XCTAssertEqual(error, .failedToFetchAccountDetails)
        }
    }

    func testRestoreAccountFromPastPurchaseErrorDueToSubscriptionFetchFailure() async throws {
        storePurchaseManager.onMostRecentTransaction = {
            return Constants.mostRecentTransactionJWS
        }

        authService.storeLoginResult = .success(Constants.storeLoginResponse)

        accountManager.onExchangeAuthTokenToAccessToken = { _ in
            return .success(Constants.accessToken)
        }

        accountManager.onFetchAccountDetails = { accessToken in
            XCTAssertEqual(accessToken, Constants.accessToken)
            return .success(AccountManager.AccountDetails(email: nil, externalID: Constants.externalID))
        }
        
        subscriptionService.getSubscriptionResult = .failure(.apiError(Constants.unknownServerError))

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: accountManager,
                                              storePurchaseManager: storePurchaseManager,
                                              subscriptionEndpointService: subscriptionService,
                                              authEndpointService: authService)
        switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertTrue(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertTrue(accountManager.fetchAccountDetailsCalled)
            XCTAssertFalse(accountManager.storeAuthTokenCalled)
            XCTAssertFalse(accountManager.storeAccountCalled)
            XCTAssertEqual(error, .failedToFetchSubscriptionDetails)
        }
    }
}
