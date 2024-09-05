//
//  AccountManagerTests.swift
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
import Common

final class AccountManagerTests: XCTestCase {

    private struct Constants {
        static let userDefaultsSuiteName = "AccountManagerTests"

        static let authToken = UUID().uuidString
        static let accessToken = UUID().uuidString
        static let externalID = UUID().uuidString

        static let email = "dax@duck.com"

        static let entitlements = [Entitlement(product: .dataBrokerProtection),
                                   Entitlement(product: .identityTheftRestoration),
                                   Entitlement(product: .networkProtection)]

        static let keychainError = AccountKeychainAccessError.keychainSaveFailure(1)
        static let invalidTokenError = APIServiceError.serverError(statusCode: 401, error: "invalid_token")
        static let unknownServerError = APIServiceError.serverError(statusCode: 401, error: "unknown_error")
    }

    var userDefaults: UserDefaults!
    var accountStorage: AccountKeychainStorageMock!
    var accessTokenStorage: SubscriptionTokenKeychainStorageMock!
    var entitlementsCache: UserDefaultsCache<[Entitlement]>!
    var subscriptionService: SubscriptionEndpointServiceMock!
    var authService: AuthEndpointServiceMock!

    var accountManager: AccountManager!

    override func setUpWithError() throws {
        userDefaults = UserDefaults(suiteName: Constants.userDefaultsSuiteName)!
        userDefaults.removePersistentDomain(forName: Constants.userDefaultsSuiteName)

        accountStorage = AccountKeychainStorageMock()
        accessTokenStorage = SubscriptionTokenKeychainStorageMock()
        entitlementsCache = UserDefaultsCache<[Entitlement]>(userDefaults: userDefaults,
                                                             key: UserDefaultsCacheKey.subscriptionEntitlements,
                                                             settings: UserDefaultsCacheSettings(defaultExpirationInterval: .minutes(20)))
        subscriptionService = SubscriptionEndpointServiceMock()
        authService = AuthEndpointServiceMock()

        accountManager = DefaultAccountManager(storage: accountStorage,
                                               accessTokenStorage: accessTokenStorage,
                                               entitlementsCache: entitlementsCache,
                                               subscriptionEndpointService: subscriptionService,
                                               authEndpointService: authService)
    }

    override func tearDownWithError() throws {
        accountStorage = nil
        accessTokenStorage = nil
        entitlementsCache = nil
        subscriptionService = nil
        authService = nil

        accountManager = nil
    }

    // MARK: - Tests for storeAuthToken

    func testStoreAuthToken() throws {
        accountManager.storeAuthToken(token: Constants.authToken)

        XCTAssertEqual(accountManager.authToken, Constants.authToken)
        XCTAssertEqual(accountStorage.authToken, Constants.authToken)
    }

    func testStoreAuthTokenFailure() async throws {
        let delegateCalled = expectation(description: "AccountManagerKeychainAccessDelegate called")
        let keychainAccessDelegateMock = AccountManagerKeychainAccessDelegateMock() { type, error in
            delegateCalled.fulfill()
            XCTAssertEqual(type, .storeAuthToken)
            XCTAssertEqual(error, Constants.keychainError)
        }

        accountStorage.mockedAccessError = Constants.keychainError
        accountManager.delegate = keychainAccessDelegateMock
        accountManager.storeAuthToken(token: Constants.authToken)

        await fulfillment(of: [delegateCalled], timeout: 0.5)
    }

    // MARK: - Tests for storeAccount

    func testStoreAccount() async throws {
        let notificationExpectation = expectation(forNotification: .accountDidSignIn, object: accountManager, handler: nil)

        accountManager.storeAccount(token: Constants.accessToken, email: Constants.email, externalID: Constants.externalID)

        XCTAssertEqual(accountManager.accessToken, Constants.accessToken)
        XCTAssertEqual(accountManager.email, Constants.email)
        XCTAssertEqual(accountManager.externalID, Constants.externalID)

        XCTAssertEqual(accessTokenStorage.accessToken, Constants.accessToken)
        XCTAssertEqual(accountStorage.email, Constants.email)
        XCTAssertEqual(accountStorage.externalID, Constants.externalID)

        await fulfillment(of: [notificationExpectation], timeout: 0.5)
    }

    func testStoreAccountUpdatingEmailToNil() throws {
        accountManager.storeAccount(token: Constants.accessToken, email: Constants.email, externalID: Constants.externalID)
        accountManager.storeAccount(token: Constants.accessToken, email: nil, externalID: Constants.externalID)

        XCTAssertEqual(accountManager.accessToken, Constants.accessToken)
        XCTAssertEqual(accountManager.email, nil)
        XCTAssertEqual(accountManager.externalID, Constants.externalID)

        XCTAssertEqual(accessTokenStorage.accessToken, Constants.accessToken)
        XCTAssertEqual(accountStorage.email, nil)
        XCTAssertEqual(accountStorage.externalID, Constants.externalID)
    }

    // MARK: - Tests for signOut

    func testSignOut() async throws {
        accountManager.storeAuthToken(token: Constants.authToken)
        accountManager.storeAccount(token: Constants.accessToken, email: Constants.email, externalID: Constants.externalID)

        XCTAssertTrue(accountManager.isUserAuthenticated)

        let notificationExpectation = expectation(forNotification: .accountDidSignOut, object: accountManager, handler: nil)

        accountManager.signOut()

        XCTAssertFalse(accountManager.isUserAuthenticated)

        XCTAssertTrue(accountStorage.clearAuthenticationStateCalled)
        XCTAssertTrue(accessTokenStorage.removeAccessTokenCalled)
        XCTAssertTrue(subscriptionService.signOutCalled)
        XCTAssertNil(entitlementsCache.get())

        await fulfillment(of: [notificationExpectation], timeout: 0.5)
    }

    func testSignOutWithoutSendingNotification() async throws {
        accountManager.storeAuthToken(token: Constants.authToken)
        accountManager.storeAccount(token: Constants.accessToken, email: Constants.email, externalID: Constants.externalID)

        XCTAssertTrue(accountManager.isUserAuthenticated)

        let notificationExpectation = expectation(forNotification: .accountDidSignOut, object: accountManager, handler: nil)
        notificationExpectation.isInverted = true

        accountManager.signOut(skipNotification: true)

        XCTAssertFalse(accountManager.isUserAuthenticated)
        await fulfillment(of: [notificationExpectation], timeout: 0.5)
    }

    // MARK: - Tests for hasEntitlement

    func testHasEntitlementIgnoringLocalCacheData() async throws {
        let productName = Entitlement.ProductName.networkProtection

        accessTokenStorage.accessToken = Constants.accessToken
        entitlementsCache.set([])
        authService.validateTokenResult = .success(ValidateTokenResponse(account: ValidateTokenResponse.Account(email: Constants.email,
                                                                                                                entitlements: Constants.entitlements,
                                                                                                                externalID: Constants.externalID)))
        XCTAssertTrue(Constants.entitlements.compactMap { $0.product }.contains(productName))

        let result = await accountManager.hasEntitlement(forProductName: productName, cachePolicy: .reloadIgnoringLocalCacheData)
        switch result {
        case .success(let success):
            XCTAssertTrue(success)
            XCTAssertTrue(authService.validateTokenCalled)
            XCTAssertEqual(entitlementsCache.get(), Constants.entitlements)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testHasEntitlementWithoutParameterUseCacheData() async throws {
        let productName = Entitlement.ProductName.networkProtection

        accessTokenStorage.accessToken = Constants.accessToken
        entitlementsCache.set(Constants.entitlements)

        XCTAssertTrue(Constants.entitlements.compactMap { $0.product }.contains(productName))

        let result = await accountManager.hasEntitlement(forProductName: productName)
        switch result {
        case .success(let success):
            XCTAssertTrue(success)
            XCTAssertFalse(authService.validateTokenCalled)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    // MARK: - Tests for updateCache

    func testUpdateEntitlementsCache() async throws {
        let updatedEntitlements = [Entitlement(product: .networkProtection)]
        XCTAssertNotEqual(Constants.entitlements, updatedEntitlements)

        entitlementsCache.set(Constants.entitlements)

        let notificationExpectation = expectation(forNotification: .entitlementsDidChange, object: accountManager, handler: nil)

        accountManager.updateCache(with: updatedEntitlements)

        XCTAssertEqual(entitlementsCache.get(), updatedEntitlements)
        await fulfillment(of: [notificationExpectation], timeout: 0.5)
    }

    func testUpdateEntitlementsCacheWithEmptyArray() async throws {
        entitlementsCache.set(Constants.entitlements)

        let notificationExpectation = expectation(forNotification: .entitlementsDidChange, object: accountManager, handler: nil)

        accountManager.updateCache(with: [])

        XCTAssertNil(entitlementsCache.get())
        await fulfillment(of: [notificationExpectation], timeout: 0.5)
    }

    func testUpdateEntitlementsCacheWithSameEntitlements() async throws {
        entitlementsCache.set(Constants.entitlements)

        let notificationNotFiredExpectation = expectation(forNotification: .entitlementsDidChange, object: accountManager, handler: nil)
        notificationNotFiredExpectation.isInverted = true

        accountManager.updateCache(with: Constants.entitlements)

        XCTAssertEqual(entitlementsCache.get(), Constants.entitlements)
        await fulfillment(of: [notificationNotFiredExpectation], timeout: 0.5)
    }

    // MARK: - Tests for fetchEntitlements

    func testFetchEntitlementsIgnoringLocalCacheData() async throws {
        accessTokenStorage.accessToken = Constants.accessToken
        entitlementsCache.set([])
        authService.validateTokenResult = .success(ValidateTokenResponse(account: ValidateTokenResponse.Account(email: Constants.email,
                                                                                                                entitlements: Constants.entitlements,
                                                                                                                externalID: Constants.externalID)))

        let result = await accountManager.fetchEntitlements(cachePolicy: .reloadIgnoringLocalCacheData)
        switch result {
        case .success(let success):
            XCTAssertEqual(success, Constants.entitlements)
            XCTAssertTrue(authService.validateTokenCalled)
            XCTAssertEqual(entitlementsCache.get(), Constants.entitlements)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testFetchEntitlementsReturnCachedData() async throws {
        accessTokenStorage.accessToken = Constants.accessToken
        entitlementsCache.set(Constants.entitlements)

        let result = await accountManager.fetchEntitlements(cachePolicy: .returnCacheDataElseLoad)
        switch result {
        case .success(let success):
            XCTAssertEqual(success, Constants.entitlements)
            XCTAssertFalse(authService.validateTokenCalled)
            XCTAssertEqual(entitlementsCache.get(), Constants.entitlements)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testFetchEntitlementsReturnCachedDataWhenCacheIsExpired() async throws {
        let updatedEntitlements = [Entitlement(product: .networkProtection)]

        accessTokenStorage.accessToken = Constants.accessToken
        entitlementsCache.set(Constants.entitlements, expires: Date.distantPast)
        authService.validateTokenResult = .success(ValidateTokenResponse(account: ValidateTokenResponse.Account(email: Constants.email,
                                                                                                                entitlements: updatedEntitlements,
                                                                                                                externalID: Constants.externalID)))

        XCTAssertNotEqual(Constants.entitlements, updatedEntitlements)

        let result = await accountManager.fetchEntitlements(cachePolicy: .returnCacheDataElseLoad)
        switch result {
        case .success(let success):
            XCTAssertEqual(success, updatedEntitlements)
            XCTAssertTrue(authService.validateTokenCalled)
            XCTAssertEqual(entitlementsCache.get(), updatedEntitlements)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testFetchEntitlementsReturnCacheDataDontLoad() async throws {
        accessTokenStorage.accessToken = Constants.accessToken
        entitlementsCache.set(Constants.entitlements)

        let result = await accountManager.fetchEntitlements(cachePolicy: .returnCacheDataDontLoad)
        switch result {
        case .success(let success):
            XCTAssertEqual(success, Constants.entitlements)
            XCTAssertFalse(authService.validateTokenCalled)
            XCTAssertEqual(entitlementsCache.get(), Constants.entitlements)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testFetchEntitlementsReturnCacheDataDontLoadWhenCacheIsExpired() async throws {
        accessTokenStorage.accessToken = Constants.accessToken
        entitlementsCache.set(Constants.entitlements, expires: Date.distantPast)

        let result = await accountManager.fetchEntitlements(cachePolicy: .returnCacheDataDontLoad)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            guard let entitlementsError = error as? DefaultAccountManager.EntitlementsError else {
                XCTFail("Incorrect error type")
                return
            }

            XCTAssertEqual(entitlementsError, .noCachedData)
        }
    }

    // MARK: - Tests for exchangeAuthTokenToAccessToken

    func testExchangeAuthTokenToAccessToken() async throws {
        authService.getAccessTokenResult = .success(.init(accessToken: Constants.accessToken))

        let result = await accountManager.exchangeAuthTokenToAccessToken(Constants.authToken)
        switch result {
        case .success(let success):
            XCTAssertEqual(success, Constants.accessToken)
            XCTAssertTrue(authService.getAccessTokenCalled)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    // MARK: - Tests for fetchAccountDetails

    func testFetchAccountDetails() async throws {
        authService.validateTokenResult = .success(ValidateTokenResponse(account: ValidateTokenResponse.Account(email: Constants.email,
                                                                                                                entitlements: Constants.entitlements,
                                                                                                                externalID: Constants.externalID)))

        let result = await accountManager.fetchAccountDetails(with: Constants.accessToken)
        switch result {
        case .success(let success):
            XCTAssertEqual(success.email, Constants.email)
            XCTAssertEqual(success.externalID, Constants.externalID)
            XCTAssertTrue(authService.validateTokenCalled)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    // MARK: - Tests for checkForEntitlements

    func testCheckForEntitlementsSuccess() async throws {
        var callCount = 0

        accessTokenStorage.accessToken = Constants.accessToken

        authService.validateTokenResult = .success(ValidateTokenResponse(account: ValidateTokenResponse.Account(email: Constants.email,
                                                                                                                entitlements: Constants.entitlements,
                                                                                                                externalID: Constants.externalID)))
        authService.onValidateToken = { _ in
            callCount += 1
        }

        let result = await accountManager.checkForEntitlements(wait: 0.1, retry: 5)

        XCTAssertTrue(result)
        XCTAssertTrue(authService.validateTokenCalled)
        XCTAssertEqual(callCount, 1)
    }

    func testCheckForEntitlementsFailure() async throws {
        var callCount = 0

        accessTokenStorage.accessToken = Constants.accessToken

        authService.validateTokenResult = .failure(Constants.unknownServerError)
        authService.onValidateToken = { _ in
            callCount += 1
        }

        let result = await accountManager.checkForEntitlements(wait: 0.1, retry: 5)

        XCTAssertFalse(result)
        XCTAssertTrue(authService.validateTokenCalled)
        XCTAssertEqual(callCount, 5)
    }

    func testCheckForEntitlementsSuccessAfterRetries() async throws {
        var callCount = 0

        accessTokenStorage.accessToken = Constants.accessToken

        authService.validateTokenResult = .failure(Constants.unknownServerError)
        authService.onValidateToken = { _ in
            callCount += 1

            if callCount == 3 {
                self.authService.validateTokenResult = .success(ValidateTokenResponse(account: ValidateTokenResponse.Account(email: Constants.email,
                                                                                                                             entitlements: Constants.entitlements,
                                                                                                                             externalID: Constants.externalID)))
            }
        }

        let result = await accountManager.checkForEntitlements(wait: 0.1, retry: 5)

        XCTAssertTrue(result)
        XCTAssertTrue(authService.validateTokenCalled)
        XCTAssertEqual(callCount, 3)
    }
}
