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
@testable import Networking
import SubscriptionTestingUtilities
import TestUtils

@available(macOS 12.0, iOS 15.0, *)
final class DefaultAppStorePurchaseFlowTests: XCTestCase {

    private var sut: DefaultAppStorePurchaseFlow!
    private var subscriptionManagerMock: SubscriptionManagerMock!
    private var storePurchaseManagerMock: StorePurchaseManagerMock!
    private var appStoreRestoreFlowMock: AppStoreRestoreFlowMock!

    override func setUp() {
        super.setUp()
        subscriptionManagerMock = SubscriptionManagerMock()
        storePurchaseManagerMock = StorePurchaseManagerMock()
        appStoreRestoreFlowMock = AppStoreRestoreFlowMock()
        sut = DefaultAppStorePurchaseFlow(
            subscriptionManager: subscriptionManagerMock,
            storePurchaseManager: storePurchaseManagerMock,
            appStoreRestoreFlow: appStoreRestoreFlowMock
        )
    }

    override func tearDown() {
        sut = nil
        subscriptionManagerMock = nil
        storePurchaseManagerMock = nil
        appStoreRestoreFlowMock = nil
        super.tearDown()
    }

    // MARK: - purchaseSubscription Tests

    func test_purchaseSubscription_withActiveSubscriptionAlreadyPresent_returnsError() async {
        appStoreRestoreFlowMock.restoreAccountFromPastPurchaseResult = .success(())

        let result = await sut.purchaseSubscription(with: "testSubscriptionID")

        XCTAssertTrue(appStoreRestoreFlowMock.restoreAccountFromPastPurchaseCalled)
        XCTAssertEqual(result, .failure(.activeSubscriptionAlreadyPresent))
    }

    func test_purchaseSubscription_withNoProductsFound_returnsError() async {
        appStoreRestoreFlowMock.restoreAccountFromPastPurchaseResult = .failure(AppStoreRestoreFlowError.missingAccountOrTransactions)

        let result = await sut.purchaseSubscription(with: "testSubscriptionID")

        XCTAssertTrue(appStoreRestoreFlowMock.restoreAccountFromPastPurchaseCalled)
        XCTAssertEqual(result, .failure(.internalError))
    }

    func test_purchaseSubscription_successfulPurchase_returnsTransactionJWS() async {
        appStoreRestoreFlowMock.restoreAccountFromPastPurchaseResult = .failure(AppStoreRestoreFlowError.missingAccountOrTransactions)
        subscriptionManagerMock.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        storePurchaseManagerMock.purchaseSubscriptionResult = .success("transactionJWS")

        let result = await sut.purchaseSubscription(with: "testSubscriptionID")

        XCTAssertTrue(storePurchaseManagerMock.purchaseSubscriptionCalled)
        XCTAssertEqual(result, .success("transactionJWS"))
    }

    func test_purchaseSubscription_purchaseCancelledByUser_returnsCancelledError() async {
        appStoreRestoreFlowMock.restoreAccountFromPastPurchaseResult = .failure(AppStoreRestoreFlowError.missingAccountOrTransactions)
        storePurchaseManagerMock.purchaseSubscriptionResult = .failure(StorePurchaseManagerError.purchaseCancelledByUser)
        subscriptionManagerMock.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        subscriptionManagerMock.resultSubscription = SubscriptionMockFactory.subscription

        let result = await sut.purchaseSubscription(with: "testSubscriptionID")

        XCTAssertEqual(result, .failure(.cancelledByUser))
    }

    func test_purchaseSubscription_purchaseFailed_returnsPurchaseFailedError() async {
        appStoreRestoreFlowMock.restoreAccountFromPastPurchaseResult = .failure(AppStoreRestoreFlowError.missingAccountOrTransactions)
        storePurchaseManagerMock.purchaseSubscriptionResult = .failure(StorePurchaseManagerError.purchaseFailed)
        subscriptionManagerMock.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        subscriptionManagerMock.resultSubscription = SubscriptionMockFactory.subscription

        let result = await sut.purchaseSubscription(with: "testSubscriptionID")

        XCTAssertEqual(result, .failure(.purchaseFailed(StorePurchaseManagerError.purchaseFailed)))
    }

    // MARK: - completeSubscriptionPurchase Tests

    func test_completeSubscriptionPurchase_withActiveSubscription_returnsSuccess() async {
        subscriptionManagerMock.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        subscriptionManagerMock.resultSubscription = SubscriptionMockFactory.subscription
        subscriptionManagerMock.confirmPurchaseResponse = .success(subscriptionManagerMock.resultSubscription!)

        let result = await sut.completeSubscriptionPurchase(with: "transactionJWS")

        XCTAssertEqual(result, .success(.completed))
    }

    func test_completeSubscriptionPurchase_withMissingEntitlements_returnsMissingEntitlementsError() async {
        subscriptionManagerMock.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        subscriptionManagerMock.resultSubscription = SubscriptionMockFactory.subscription
        subscriptionManagerMock.confirmPurchaseResponse = .success(subscriptionManagerMock.resultSubscription!)

        let result = await sut.completeSubscriptionPurchase(with: "transactionJWS")

        XCTAssertEqual(result, .failure(.missingEntitlements))
    }

    func test_completeSubscriptionPurchase_withExpiredSubscription_returnsPurchaseFailedError() async {
        subscriptionManagerMock.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        subscriptionManagerMock.resultSubscription = SubscriptionMockFactory.expiredSubscription
        subscriptionManagerMock.confirmPurchaseResponse = .success(subscriptionManagerMock.resultSubscription!)

        let result = await sut.completeSubscriptionPurchase(with: "transactionJWS")

        XCTAssertEqual(result, .failure(.purchaseFailed(AppStoreRestoreFlowError.subscriptionExpired)))
    }

    func test_completeSubscriptionPurchase_withConfirmPurchaseError_returnsPurchaseFailedError() async {
        subscriptionManagerMock.resultSubscription = SubscriptionMockFactory.subscription
        subscriptionManagerMock.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        subscriptionManagerMock.confirmPurchaseResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.badRequest))

        let result = await sut.completeSubscriptionPurchase(with: "transactionJWS")
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .purchaseFailed(_):
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
}

/*
final class AppStorePurchaseFlowTests: XCTestCase {

    private struct Constants {
        static let externalID = UUID().uuidString
        static let email = "dax@duck.com"

        static let productID = UUID().uuidString
        static let transactionJWS = "dGhpcyBpcyBub3QgYSByZWFsIEFw(...)cCBTdG9yZSB0cmFuc2FjdGlvbiBKV1M="
    }

     var mockSubscriptionManager: SubscriptionManagerMock!
     var mockStorePurchaseManager: StorePurchaseManagerMock!
     var mockAppStoreRestoreFlow: AppStoreRestoreFlowMock!

    var appStorePurchaseFlow: AppStorePurchaseFlow!

    override func setUpWithError() throws {
        mockSubscriptionManager = SubscriptionManagerMock()
        mockStorePurchaseManager = StorePurchaseManagerMock()
        mockAppStoreRestoreFlow = AppStoreRestoreFlowMock()

        appStorePurchaseFlow = DefaultAppStorePurchaseFlow(subscriptionManager: mockSubscriptionManager,
                                                           storePurchaseManager: mockStorePurchaseManager,
                                                           appStoreRestoreFlow: mockAppStoreRestoreFlow)
    }

    override func tearDownWithError() throws {
        mockSubscriptionManager = nil
        mockStorePurchaseManager = nil
        mockAppStoreRestoreFlow = nil
        appStorePurchaseFlow = nil
    }

    // MARK: - Tests for purchaseSubscription

    func testPurchaseSubscriptionSuccess() async throws {
        // Given

        mockAppStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.missingAccountOrTransactions)
//        authService.createAccountResult = .success(CreateAccountResponse(authToken: Constants.authToken,
//                                                                         externalID: Constants.externalID,
//                                                                         status: "created"))
//        accountManager.exchangeAuthTokenToAccessTokenResult = .success(Constants.accessToken)
//        accountManager.fetchAccountDetailsResult = .success((email: "", externalID: Constants.externalID))
//        storePurchaseManager.purchaseSubscriptionResult = .success(Constants.transactionJWS)

        // When
        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID) {
        case .success(let success):
//            // Then
//            XCTAssertTrue(appStoreRestoreFlow.restoreAccountFromPastPurchaseCalled)
//            XCTAssertTrue(authService.createAccountCalled)
//            XCTAssertTrue(accountManager.exchangeAuthTokenToAccessTokenCalled)
//            XCTAssertTrue(accountManager.storeAuthTokenCalled)
//            XCTAssertTrue(accountManager.storeAccountCalled)
//            XCTAssertTrue(storePurchaseManager.purchaseSubscriptionCalled)
//            XCTAssertEqual(success, Constants.transactionJWS)
            break
        case .failure(let error):
            XCTFail("Unexpected failure: \(String(reflecting: error))")
        }
    }

    func testPurchaseSubscriptionSuccessRepurchaseForAppStoreSubscription() async throws {
        // Given
        accountManager.authToken = Constants.authToken
        accountManager.accessToken = Constants.accessToken
        accountManager.externalID = Constants.externalID
        accountManager.email = Constants.email

        let expiredSubscription = SubscriptionMockFactory.expiredSubscription

        XCTAssertFalse(expiredSubscription.isActive)
        XCTAssertEqual(expiredSubscription.platform, .apple)
        XCTAssertTrue(accountManager.isUserAuthenticated)

        subscriptionService.getSubscriptionResult = .success(expiredSubscription)
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.subscriptionExpired(accountDetails: .init(authToken: Constants.authToken,
                                                                                                                       accessToken: Constants.accessToken,
                                                                                                                       externalID: Constants.externalID,
                                                                                                                       email: Constants.email)))
        storePurchaseManager.purchaseSubscriptionResult = .success(Constants.transactionJWS)

        // When
        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success(let success):
            // Then
            XCTAssertTrue(appStoreRestoreFlow.restoreAccountFromPastPurchaseCalled)
            XCTAssertFalse(authService.createAccountCalled)
            XCTAssertFalse(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertTrue(storePurchaseManager.purchaseSubscriptionCalled)
            XCTAssertEqual(success, Constants.transactionJWS)
            XCTAssertEqual(accountManager.externalID, Constants.externalID)
            XCTAssertEqual(accountManager.email, Constants.email)
        case .failure(let error):
            XCTFail("Unexpected failure: \(String(reflecting: error))")
        }
    }

    func testPurchaseSubscriptionSuccessRepurchaseForNonAppStoreSubscription() async throws {
        // Given
        accountManager.authToken = Constants.authToken
        accountManager.accessToken = Constants.accessToken
        accountManager.externalID = Constants.externalID

        let subscription = SubscriptionMockFactory.expiredStripeSubscription

        XCTAssertFalse(subscription.isActive)
        XCTAssertNotEqual(subscription.platform, .apple)
        XCTAssertTrue(accountManager.isUserAuthenticated)

        subscriptionService.getSubscriptionResult = .success(subscription)
        storePurchaseManager.purchaseSubscriptionResult = .success(Constants.transactionJWS)

        // When
        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success:
            // Then
            XCTAssertFalse(appStoreRestoreFlow.restoreAccountFromPastPurchaseCalled)
            XCTAssertFalse(authService.createAccountCalled)
            XCTAssertEqual(accountManager.externalID, Constants.externalID)
        case .failure(let error):
            XCTFail("Unexpected failure: \(String(reflecting: error))")
        }
    }

    func testPurchaseSubscriptionErrorWhenActiveSubscriptionRestoredFromAppStore() async throws {
        // Given
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .success(Void())

        // When
        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertFalse(authService.createAccountCalled)
            XCTAssertFalse(storePurchaseManager.purchaseSubscriptionCalled)
            XCTAssertEqual(error, .activeSubscriptionAlreadyPresent)
        }
    }

    func testPurchaseSubscriptionErrorWhenAccountCreationFails() async throws {
        // Given
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.missingAccountOrTransactions)
        authService.createAccountResult = .failure(.unknownServerError)

        // When
        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertTrue(authService.createAccountCalled)
            XCTAssertFalse(storePurchaseManager.purchaseSubscriptionCalled)
            XCTAssertEqual(error, .accountCreationFailed)
        }
    }

    func testPurchaseSubscriptionErrorWhenAppStorePurchaseFails() async throws {
        // Given
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.missingAccountOrTransactions)
        authService.createAccountResult = .success(CreateAccountResponse(authToken: Constants.authToken,
                                                                         externalID: Constants.externalID,
                                                                         status: "created"))
        accountManager.exchangeAuthTokenToAccessTokenResult = .success(Constants.accessToken)
        accountManager.fetchAccountDetailsResult = .success((email: "", externalID: Constants.externalID))
        storePurchaseManager.purchaseSubscriptionResult = .failure(.productNotFound)

        // When
        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertTrue(authService.createAccountCalled)
            XCTAssertTrue(storePurchaseManager.purchaseSubscriptionCalled)
            XCTAssertEqual(error, .purchaseFailed)
        }
    }

    func testPurchaseSubscriptionErrorWhenAppStorePurchaseCancelledByUser() async throws {
        // Given
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.missingAccountOrTransactions)
        authService.createAccountResult = .success(CreateAccountResponse(authToken: Constants.authToken,
                                                                         externalID: Constants.externalID,
                                                                         status: "created"))
        accountManager.exchangeAuthTokenToAccessTokenResult = .success(Constants.accessToken)
        accountManager.fetchAccountDetailsResult = .success((email: "", externalID: Constants.externalID))
        storePurchaseManager.purchaseSubscriptionResult = .failure(.purchaseCancelledByUser)

        // When
        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertTrue(authService.createAccountCalled)
            XCTAssertTrue(storePurchaseManager.purchaseSubscriptionCalled)
            XCTAssertEqual(error, .cancelledByUser)
        }
    }

    // MARK: - Tests for completeSubscriptionPurchase

    func testCompleteSubscriptionPurchaseSuccess() async throws {
        // Given
        accountManager.accessToken = Constants.accessToken
        subscriptionService.confirmPurchaseResult = .success(ConfirmPurchaseResponse(email: nil,
                                                                                     entitlements: [],
                                                                                     subscription: SubscriptionMockFactory.subscription))

        subscriptionService.onUpdateCache = { subscription in
            XCTAssertEqual(subscription, SubscriptionMockFactory.subscription)
        }

        // When
        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: Constants.transactionJWS) {
        case .success(let success):
            // Then
            XCTAssertTrue(subscriptionService.updateCacheWithSubscriptionCalled)
            XCTAssertTrue(accountManager.updateCacheWithEntitlementsCalled)
            XCTAssertEqual(success.type, "completed")
        case .failure(let error):
            XCTFail("Unexpected failure: \(String(reflecting: error))")
        }
    }

    func testCompleteSubscriptionPurchaseErrorDueToMissingAccessToken() async throws {
        // Given
        XCTAssertNil(accountManager.accessToken)

        // When
        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: Constants.transactionJWS) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertEqual(error, .missingEntitlements)
        }
    }

    func testCompleteSubscriptionPurchaseErrorDueToFailedPurchaseConfirmation() async throws {
        // Given
        accountManager.accessToken = Constants.accessToken
        subscriptionService.confirmPurchaseResult = .failure(Constants.unknownServerError)

        // When
        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: Constants.transactionJWS) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertEqual(error, .missingEntitlements)
        }
    }
 }
*/
