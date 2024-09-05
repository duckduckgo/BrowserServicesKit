//
//  SubscriptionEndpointServiceTests.swift
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

final class SubscriptionEndpointServiceTests: XCTestCase {

    private struct Constants {
        static let authToken = UUID().uuidString
        static let accessToken = UUID().uuidString
        static let externalID = UUID().uuidString
        static let email = "dax@duck.com"
        
        static let mostRecentTransactionJWS = "dGhpcyBpcyBub3QgYSByZWFsIEFw(...)cCBTdG9yZSB0cmFuc2FjdGlvbiBKV1M="

        static let subscription = SubscriptionMockFactory.subscription

        static let customerPortalURL = "https://billing.stripe.com/p/session/test_ABC"

        static let authorizationHeader = ["Authorization": "Bearer TOKEN"]

        static let unknownServerError = APIServiceError.serverError(statusCode: 401, error: "unknown_error")
    }

    var apiService: APIServiceMock!
    var subscriptionService: SubscriptionEndpointService!

    override func setUpWithError() throws {
        apiService = APIServiceMock()
        subscriptionService = DefaultSubscriptionEndpointService(currentServiceEnvironment: .staging, apiService: apiService)
    }

    override func tearDownWithError() throws {
        apiService = nil
        subscriptionService = nil
    }

    // MARK: - Tests for

    func testGetSubscriptionCall() async throws {
        let apiServiceCalledExpectation = expectation(description: "apiService")

        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.onExecuteAPICall = { parameters in
            let (method, endpoint, headers, _) = parameters;

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "GET")
            XCTAssertEqual(endpoint, "subscription")
            XCTAssertEqual(headers, Constants.authorizationHeader)
        }

        _ = await subscriptionService.getSubscription(accessToken: Constants.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testGetSubscriptionSuccess() async throws {
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockResponseJSONData = """
        {
            "productId": "\(Constants.subscription.productId)",
            "name": "\(Constants.subscription.name)",
            "billingPeriod": "\(Constants.subscription.billingPeriod.rawValue)",
            "startedAt": \(Constants.subscription.startedAt.timeIntervalSince1970*1000),
            "expiresOrRenewsAt": \(Constants.subscription.expiresOrRenewsAt.timeIntervalSince1970*1000),
            "platform": "\(Constants.subscription.platform.rawValue)",
            "status": "\(Constants.subscription.status.rawValue)"
        }
        """.data(using: .utf8)!

        let result = await subscriptionService.getSubscription(accessToken: Constants.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)
        switch result {
        case .success(let success):
            XCTAssertEqual(success.productId, Constants.subscription.productId)
            XCTAssertEqual(success.name, Constants.subscription.name)
            XCTAssertEqual(success.billingPeriod, Constants.subscription.billingPeriod)
            XCTAssertEqual(success.startedAt.timeIntervalSince1970,
                           Constants.subscription.startedAt.timeIntervalSince1970,
                           accuracy: 0.001)
            XCTAssertEqual(success.expiresOrRenewsAt.timeIntervalSince1970,
                           Constants.subscription.expiresOrRenewsAt.timeIntervalSince1970,
                           accuracy: 0.001)
            XCTAssertEqual(success.platform, Constants.subscription.platform)
            XCTAssertEqual(success.status, Constants.subscription.status)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testGetSubscriptionError() async throws {
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockAPICallError = Constants.unknownServerError

        let result = await subscriptionService.getSubscription(accessToken: Constants.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }

    // MARK: - Tests for getProducts

    func testGetProductsCall() async throws {
        let apiServiceCalledExpectation = expectation(description: "apiService")

        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.onExecuteAPICall = { parameters in
            let (method, endpoint, headers, _) = parameters;

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "GET")
            XCTAssertEqual(endpoint, "products")
            XCTAssertNil(headers)
        }

        _ = await subscriptionService.getProducts()
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testGetProductsSuccess() async throws {
        apiService.mockResponseJSONData = """
        [
            {
                "productId":"ddg-privacy-pro-sandbox-monthly-renews-us",
                "productLabel":"Monthly Subscription",
                "billingPeriod":"Monthly",
                "price":"9.99",
                "currency":"USD"
            },
            {
                "productId":"ddg-privacy-pro-sandbox-yearly-renews-us",
                "productLabel":"Yearly Subscription",
                "billingPeriod":"Yearly",
                "price":"99.99",
                "currency":"USD"
            }
        ]
        """.data(using: .utf8)!

        let result = await subscriptionService.getProducts()
        switch result {
        case .success(let success):
            XCTAssertEqual(success.count, 2)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testGetProductsError() async throws {
        apiService.mockAPICallError = Constants.unknownServerError

        let result = await subscriptionService.getProducts()
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }

    // MARK: - Tests for getCustomerPortalURL

    func testGetCustomerPortalURLCall() async throws {
        let apiServiceCalledExpectation = expectation(description: "apiService")

        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.onExecuteAPICall = { parameters in
            let (method, endpoint, headers, _) = parameters;

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "GET")
            XCTAssertEqual(endpoint, "checkout/portal")
            XCTAssertEqual(headers?.count, 2)
            XCTAssertEqual(headers?["externalAccountId"], Constants.externalID)

            if let (authorizationHeaderKey, authorizationHeaderValue) = Constants.authorizationHeader.first {
                XCTAssertEqual(headers?[authorizationHeaderKey], authorizationHeaderValue)
            }
        }

        _ = await subscriptionService.getCustomerPortalURL(accessToken: Constants.accessToken, externalID: Constants.externalID)
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testGetCustomerPortalURLSuccess() async throws {
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockResponseJSONData = """
        {
            "customerPortalUrl":"\(Constants.customerPortalURL)"
        }
        """.data(using: .utf8)!

        let result = await subscriptionService.getCustomerPortalURL(accessToken: Constants.accessToken, externalID: Constants.externalID)
        switch result {
        case .success(let success):
            XCTAssertEqual(success.customerPortalUrl, Constants.customerPortalURL)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testGetCustomerPortalURLError() async throws {
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockAPICallError = Constants.unknownServerError

        let result = await subscriptionService.getCustomerPortalURL(accessToken: Constants.accessToken, externalID: Constants.externalID)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }

    // MARK: - Tests for confirmPurchase

    func testConfirmPurchaseCall() async throws {
        let apiServiceCalledExpectation = expectation(description: "apiService")

        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.onExecuteAPICall = { parameters in
            let (method, endpoint, headers, body) = parameters;

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "POST")
            XCTAssertEqual(endpoint, "purchase/confirm/apple")
            XCTAssertEqual(headers, Constants.authorizationHeader)
            XCTAssertNotNil(body)

            if let bodyDict = try? JSONDecoder().decode([String: String].self, from: body!) {
                XCTAssertEqual(bodyDict["signedTransactionInfo"], Constants.mostRecentTransactionJWS)
            } else {
                XCTFail("Failed to decode body")
            }
        }

        _ = await subscriptionService.confirmPurchase(accessToken: Constants.accessToken, signature: Constants.mostRecentTransactionJWS)
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testConfirmPurchaseSuccess() async throws {
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockResponseJSONData = """
        {
            "email":"",
            "entitlements":
            [
                {"product":"Data Broker Protection","name":"subscriber"},
                {"product":"Identity Theft Restoration","name":"subscriber"},
                {"product":"Network Protection","name":"subscriber"}
            ],
            "subscription":
            {
                "productId": "\(Constants.subscription.productId)",
                "name": "\(Constants.subscription.name)",
                "billingPeriod": "\(Constants.subscription.billingPeriod.rawValue)",
                "startedAt": \(Constants.subscription.startedAt.timeIntervalSince1970*1000),
                "expiresOrRenewsAt": \(Constants.subscription.expiresOrRenewsAt.timeIntervalSince1970*1000),
                "platform": "\(Constants.subscription.platform.rawValue)",
                "status": "\(Constants.subscription.status.rawValue)"
            }
        }
        """.data(using: .utf8)!

        let result = await subscriptionService.confirmPurchase(accessToken: Constants.accessToken, signature: Constants.mostRecentTransactionJWS)
        switch result {
        case .success(let success):
            XCTAssertEqual(success.entitlements.count, 3)
            XCTAssertEqual(success.subscription.productId, Constants.subscription.productId)
            XCTAssertEqual(success.subscription.name, Constants.subscription.name)
            XCTAssertEqual(success.subscription.billingPeriod, Constants.subscription.billingPeriod)
            XCTAssertEqual(success.subscription.startedAt.timeIntervalSince1970,
                           Constants.subscription.startedAt.timeIntervalSince1970,
                           accuracy: 0.001)
            XCTAssertEqual(success.subscription.expiresOrRenewsAt.timeIntervalSince1970, 
                           Constants.subscription.expiresOrRenewsAt.timeIntervalSince1970,
                           accuracy: 0.001)
            XCTAssertEqual(success.subscription.platform, Constants.subscription.platform)
            XCTAssertEqual(success.subscription.status, Constants.subscription.status)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testConfirmPurchaseError() async throws {
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockAPICallError = Constants.unknownServerError

        let result = await subscriptionService.confirmPurchase(accessToken: Constants.accessToken, signature: Constants.mostRecentTransactionJWS)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }
}
