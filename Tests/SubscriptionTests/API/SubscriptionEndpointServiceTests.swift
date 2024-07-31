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
        static let authToken = "this-is-auth-token"
        static let accessToken = "this-is-access-token"
        static let externalID = "0084026b-0340-4880-0000-0006026abd00"
        static let authorizationHeader = ["Authorization": "Bearer TOKEN"]
        static let transactionSignature = "APPSTORETRANSACTIONSIGNATUREJWT"

        static let subscriptionProductID = "ddg-privacy-pro-tests-monthly"
        static let subscriptionName = "Monthly Subscription"
        static let subscriptionBillingPeriod = Subscription.BillingPeriod.monthly
        static let subscriptionStartedAtDate = Date(timeIntervalSince1970: 1722323477)
        static let subscriptionExpiresDate = Date(timeIntervalSince1970: 1722323657)
        static let subscriptionPlatform = Subscription.Platform.stripe
        static let subscriptionStatus = Subscription.Status.autoRenewable

        static let customerPortalURL = "https://billing.stripe.com/p/session/test_ABC"
        
        static let unknownServerError = APIServiceError.serverError(statusCode: 401, error: "unknown_error")
    }

    func testGetSubscriptionCall() async throws {
        let apiServiceCalledExpectation = expectation(description: "apiService")

        let onExecute: (APIServiceMock.ExecuteAPICallParameters) -> Void = { parameters in
            let (method, endpoint, headers, _) = parameters;

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "GET")
            XCTAssertEqual(endpoint, "subscription")
            XCTAssertEqual(headers, Constants.authorizationHeader)
        }

        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, onExecuteAPICall: onExecute)
        let subscriptionService = DefaultSubscriptionEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        _ = await subscriptionService.getSubscription(accessToken: Constants.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testGetSubscriptionSuccess() async throws {
        let json = """
        {
            "productId": "\(Constants.subscriptionProductID)",
            "name": "\(Constants.subscriptionName)",
            "billingPeriod": "\(Constants.subscriptionBillingPeriod.rawValue)",
            "startedAt": \(Constants.subscriptionStartedAtDate.timeIntervalSince1970*1000),
            "expiresOrRenewsAt": \(Constants.subscriptionExpiresDate.timeIntervalSince1970*1000),
            "platform": "\(Constants.subscriptionPlatform.rawValue)",
            "status": "\(Constants.subscriptionStatus.rawValue)"
        }
        """.data(using: .utf8)!

        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, mockResponseJSONData: json)
        let subscriptionService = DefaultSubscriptionEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        let result = await subscriptionService.getSubscription(accessToken: Constants.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)
        switch result {
        case .success(let success):
            XCTAssertEqual(success.productId, Constants.subscriptionProductID)
            XCTAssertEqual(success.name, Constants.subscriptionName)
            XCTAssertEqual(success.billingPeriod, Constants.subscriptionBillingPeriod)
            XCTAssertEqual(success.startedAt, Constants.subscriptionStartedAtDate)
            XCTAssertEqual(success.expiresOrRenewsAt, Constants.subscriptionExpiresDate)
            XCTAssertEqual(success.platform, Constants.subscriptionPlatform)
            XCTAssertEqual(success.status, Constants.subscriptionStatus)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testGetSubscriptionError() async throws {
        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, mockAPICallError: Constants.unknownServerError)
        let subscriptionService = DefaultSubscriptionEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        let result = await subscriptionService.getSubscription(accessToken: Constants.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }

    func testGetProductsCall() async throws {
        let apiServiceCalledExpectation = expectation(description: "apiService")

        let onExecute: (APIServiceMock.ExecuteAPICallParameters) -> Void = { parameters in
            let (method, endpoint, headers, _) = parameters;

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "GET")
            XCTAssertEqual(endpoint, "products")
            XCTAssertNil(headers)
        }

        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, onExecuteAPICall: onExecute)
        let subscriptionService = DefaultSubscriptionEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        _ = await subscriptionService.getProducts()
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testGetProductsSuccess() async throws {
        let json = """
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

        let apiService = APIServiceMock(mockResponseJSONData: json)
        let subscriptionService = DefaultSubscriptionEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        let result = await subscriptionService.getProducts()
        switch result {
        case .success(let success):
            XCTAssertEqual(success.count, 2)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testGetProductsError() async throws {
        let apiService = APIServiceMock(mockAPICallError: Constants.unknownServerError)
        let subscriptionService = DefaultSubscriptionEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        let result = await subscriptionService.getProducts()
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }

    func testGetCustomerPortalURLCall() async throws {
        let apiServiceCalledExpectation = expectation(description: "apiService")

        let onExecute: (APIServiceMock.ExecuteAPICallParameters) -> Void = { parameters in
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

        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, onExecuteAPICall: onExecute)
        let subscriptionService = DefaultSubscriptionEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        _ = await subscriptionService.getCustomerPortalURL(accessToken: Constants.accessToken, externalID: Constants.externalID)
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testGetCustomerPortalURLSuccess() async throws {
        let json = """
        {
            "customerPortalUrl":"\(Constants.customerPortalURL)"
        }
        """.data(using: .utf8)!

        let apiService = APIServiceMock(mockResponseJSONData: json)
        let subscriptionService = DefaultSubscriptionEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        let result = await subscriptionService.getCustomerPortalURL(accessToken: Constants.accessToken, externalID: Constants.externalID)
        switch result {
        case .success(let success):
            XCTAssertEqual(success.customerPortalUrl, Constants.customerPortalURL)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testGetCustomerPortalURLError() async throws {
        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, mockAPICallError: Constants.unknownServerError)
        let subscriptionService = DefaultSubscriptionEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        let result = await subscriptionService.getCustomerPortalURL(accessToken: Constants.accessToken, externalID: Constants.externalID)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }

    func testConfirmPurchaseCall() async throws {
        let apiServiceCalledExpectation = expectation(description: "apiService")

        let onExecute: (APIServiceMock.ExecuteAPICallParameters) -> Void = { parameters in
            let (method, endpoint, headers, body) = parameters;

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "POST")
            XCTAssertEqual(endpoint, "purchase/confirm/apple")
            XCTAssertEqual(headers, Constants.authorizationHeader)
            XCTAssertNotNil(body)

            if let bodyDict = try? JSONDecoder().decode([String: String].self, from: body!) {
                XCTAssertEqual(bodyDict["signedTransactionInfo"], Constants.transactionSignature)
            } else {
                XCTFail("Failed to decode body")
            }
        }

        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, onExecuteAPICall: onExecute)
        let subscriptionService = DefaultSubscriptionEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        _ = await subscriptionService.confirmPurchase(accessToken: Constants.accessToken, signature: Constants.transactionSignature)
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testConfirmPurchaseSuccess() async throws {
        let json = """
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
                "productId": "\(Constants.subscriptionProductID)",
                "name": "\(Constants.subscriptionName)",
                "billingPeriod": "\(Constants.subscriptionBillingPeriod.rawValue)",
                "startedAt": \(Constants.subscriptionStartedAtDate.timeIntervalSince1970*1000),
                "expiresOrRenewsAt": \(Constants.subscriptionExpiresDate.timeIntervalSince1970*1000),
                "platform": "\(Constants.subscriptionPlatform.rawValue)",
                "status": "\(Constants.subscriptionStatus.rawValue)"
            }
        }
        """.data(using: .utf8)!

        let apiService = APIServiceMock(mockResponseJSONData: json)
        let subscriptionService = DefaultSubscriptionEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        let result = await subscriptionService.confirmPurchase(accessToken: Constants.accessToken, signature: Constants.transactionSignature)
        switch result {
        case .success(let success):
            XCTAssertEqual(success.entitlements.count, 3)
            XCTAssertEqual(success.subscription.productId, Constants.subscriptionProductID)
            XCTAssertEqual(success.subscription.name, Constants.subscriptionName)
            XCTAssertEqual(success.subscription.billingPeriod, Constants.subscriptionBillingPeriod)
            XCTAssertEqual(success.subscription.startedAt, Constants.subscriptionStartedAtDate)
            XCTAssertEqual(success.subscription.expiresOrRenewsAt, Constants.subscriptionExpiresDate)
            XCTAssertEqual(success.subscription.platform, Constants.subscriptionPlatform)
            XCTAssertEqual(success.subscription.status, Constants.subscriptionStatus)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testConfirmPurchaseError() async throws {
        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, mockAPICallError: Constants.unknownServerError)
        let subscriptionService = DefaultSubscriptionEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        let result = await subscriptionService.confirmPurchase(accessToken: Constants.accessToken, signature: Constants.transactionSignature)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }
}
