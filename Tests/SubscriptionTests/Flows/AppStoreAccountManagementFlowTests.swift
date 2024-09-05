//
//  AppStoreAccountManagementFlowTests.swift
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

final class AppStoreAccountManagementFlowTests: XCTestCase {

    private struct Constants {
        static let oldAuthToken = UUID().uuidString
        static let newAuthToken = UUID().uuidString

        static let externalID = UUID ().uuidString
        static let otherExternalID = UUID().uuidString

        static let mostRecentTransactionJWS = "dGhpcyBpcyBub3QgYSByZWFsIEFw(...)cCBTdG9yZSB0cmFuc2FjdGlvbiBKV1M="

        static let invalidTokenError = APIServiceError.serverError(statusCode: 401, error: "invalid_token")

        static let account = ValidateTokenResponse.Account(email: nil,
                                                           entitlements: [],
                                                           externalID: externalID)
    }

    var accountManager: AccountManagerMock!
    var authEndpointService: AuthEndpointServiceMock!
    var storePurchaseManager: StorePurchaseManagerMock!

    var appStoreAccountManagementFlow: AppStoreAccountManagementFlow!

    override func setUpWithError() throws {
        accountManager = AccountManagerMock()
        authEndpointService = AuthEndpointServiceMock()
        storePurchaseManager = StorePurchaseManagerMock()

        appStoreAccountManagementFlow = DefaultAppStoreAccountManagementFlow(authEndpointService: authEndpointService,
                                                                             storePurchaseManager: storePurchaseManager,
                                                                             accountManager: accountManager)
    }

    override func tearDownWithError() throws {
        accountManager = nil
        authEndpointService = nil
        storePurchaseManager = nil

        appStoreAccountManagementFlow = nil
    }

    // MARK: - Tests for refreshAuthTokenIfNeeded

    func testRefreshAuthTokenIfNeededSuccess() async throws {
        accountManager.authToken = Constants.oldAuthToken
        accountManager.externalID = Constants.externalID

        authEndpointService.validateTokenResult = .failure(Constants.invalidTokenError)

        storePurchaseManager.mostRecentTransactionResult = Constants.mostRecentTransactionJWS

        authEndpointService.storeLoginResult = .success(StoreLoginResponse(authToken: Constants.newAuthToken,
                                                                           email: "",
                                                                           externalID: Constants.externalID,
                                                                           id: 1,
                                                                           status: "ok"))

        switch await appStoreAccountManagementFlow.refreshAuthTokenIfNeeded() {
        case .success(let success):
            XCTAssertTrue(storePurchaseManager.mostRecentTransactionCalled)
            XCTAssertEqual(success, Constants.newAuthToken)
        case .failure(let error):
            XCTFail("Unexpected failure: \(String(reflecting: error))")
        }
    }

    func testRefreshAuthTokenIfNeededSuccessButNotRefreshedIfStillValid() async throws {
        accountManager.authToken = Constants.oldAuthToken

        authEndpointService.validateTokenResult = .success(ValidateTokenResponse(account: Constants.account))

        let flow = DefaultAppStoreAccountManagementFlow(authEndpointService: authEndpointService,
                                                        storePurchaseManager: storePurchaseManager,
                                                        accountManager: accountManager)
        switch await flow.refreshAuthTokenIfNeeded() {
        case .success(let success):
            XCTAssertEqual(success, Constants.oldAuthToken)
        case .failure(let error):
            XCTFail("Unexpected failure: \(String(reflecting: error))")
        }
    }

    func testRefreshAuthTokenIfNeededSuccessButNotRefreshedIfStoreLoginRetrievedDifferentAccount() async throws {
        accountManager.authToken = Constants.oldAuthToken
        accountManager.externalID = Constants.externalID

        authEndpointService.validateTokenResult = .failure(Constants.invalidTokenError)

        storePurchaseManager.mostRecentTransactionResult = Constants.mostRecentTransactionJWS

        authEndpointService.storeLoginResult = .success(StoreLoginResponse(authToken: Constants.newAuthToken,
                                                                           email: "",
                                                                           externalID: Constants.otherExternalID,
                                                                           id: 1,
                                                                           status: "ok"))

        let flow = DefaultAppStoreAccountManagementFlow(authEndpointService: authEndpointService,
                                                        storePurchaseManager: storePurchaseManager,
                                                        accountManager: accountManager)
        switch await flow.refreshAuthTokenIfNeeded() {
        case .success(let success):
            XCTAssertTrue(storePurchaseManager.mostRecentTransactionCalled)
            XCTAssertEqual(success, Constants.oldAuthToken)
        case .failure(let error):
            XCTFail("Unexpected failure: \(String(reflecting: error))")
        }
    }

    func testRefreshAuthTokenIfNeededErrorDueToNoPastTransactions() async throws {
        accountManager.authToken = Constants.oldAuthToken

        authEndpointService.validateTokenResult = .failure(Constants.invalidTokenError)

        storePurchaseManager.mostRecentTransactionResult = nil

        let flow = DefaultAppStoreAccountManagementFlow(authEndpointService: authEndpointService,
                                                        storePurchaseManager: storePurchaseManager,
                                                        accountManager: accountManager)
        switch await flow.refreshAuthTokenIfNeeded() {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertTrue(storePurchaseManager.mostRecentTransactionCalled)
            XCTAssertEqual(error, .noPastTransaction)
        }
    }

    func testRefreshAuthTokenIfNeededErrorDueToStoreLoginFailure() async throws {
        accountManager.authToken = Constants.oldAuthToken

        authEndpointService.validateTokenResult = .failure(Constants.invalidTokenError)

        storePurchaseManager.mostRecentTransactionResult = Constants.mostRecentTransactionJWS

        authEndpointService.storeLoginResult = .failure(.unknownServerError)

        let flow = DefaultAppStoreAccountManagementFlow(authEndpointService: authEndpointService,
                                                        storePurchaseManager: storePurchaseManager,
                                                        accountManager: accountManager)
        switch await flow.refreshAuthTokenIfNeeded() {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertTrue(storePurchaseManager.mostRecentTransactionCalled)
            XCTAssertEqual(error, .authenticatingWithTransactionFailed)
        }
    }
}
