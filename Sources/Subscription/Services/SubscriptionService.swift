//
//  SubscriptionService.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Foundation
import Common

public struct SubscriptionService: APIService {

    public static let session = {
        let configuration = URLSessionConfiguration.ephemeral
        return URLSession(configuration: configuration)
    }()

    public static var baseURL: URL {
        switch SubscriptionPurchaseEnvironment.currentServiceEnvironment {
        case .production:
            URL(string: "https://subscriptions.duckduckgo.com/api")!
        case .staging:
            URL(string: "https://subscriptions-dev.duckduckgo.com/api")!
        }
    }

    // MARK: -

    public static func getSubscriptionDetails(token: String) async -> Result<GetSubscriptionDetailsResponse, APIServiceError> {
        let result: Result<GetSubscriptionDetailsResponse, APIServiceError> = await executeAPICall(method: "GET", endpoint: "subscription", headers: makeAuthorizationHeader(for: token))

        switch result {
        case .success(let response):
            cachedSubscriptionDetailsResponse = response
        case .failure:
            cachedSubscriptionDetailsResponse = nil
        }

        return result
    }

    public typealias GetSubscriptionDetailsResponse = Subscription

    public static var cachedSubscriptionDetailsResponse: GetSubscriptionDetailsResponse?

    // MARK: -

    public static func getProducts() async -> Result<GetProductsResponse, APIServiceError> {
        await executeAPICall(method: "GET", endpoint: "products")
    }

    public typealias GetProductsResponse = [GetProductsItem]

    public struct GetProductsItem: Decodable {
        public let productId: String
        public let productLabel: String
        public let billingPeriod: String
        public let price: String
        public let currency: String
    }

    // MARK: -

    public static func getCustomerPortalURL(accessToken: String, externalID: String) async -> Result<GetCustomerPortalURLResponse, APIServiceError> {
        var headers = makeAuthorizationHeader(for: accessToken)
        headers["externalAccountId"] = externalID
        return await executeAPICall(method: "GET", endpoint: "checkout/portal", headers: headers)
    }

    public struct GetCustomerPortalURLResponse: Decodable {
        public let customerPortalUrl: String
    }

    // MARK: -

    public static func confirmPurchase(accessToken: String, signature: String) async -> Result<ConfirmPurchaseResponse, APIServiceError> {
        let headers = makeAuthorizationHeader(for: accessToken)
        let bodyDict = ["signedTransactionInfo": signature]

        guard let bodyData = try? JSONEncoder().encode(bodyDict) else { return .failure(.encodingError) }
        return await executeAPICall(method: "POST", endpoint: "purchase/confirm/apple", headers: headers, body: bodyData)
    }

    public struct ConfirmPurchaseResponse: Decodable {
        public let email: String?
        public let entitlements: [Entitlement]
        public let subscription: Subscription
    }
}
