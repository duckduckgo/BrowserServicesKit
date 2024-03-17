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

import Common
import Foundation

public protocol SubscriptionServiceProtocol {
    func getSubscription(accessToken: String) async -> Result<GetSubscriptionResponse, SubscriptionServiceError>
    func getSubscription(accessToken: String, cachePolicy: CachePolicy) async -> Result<GetSubscriptionResponse, SubscriptionServiceError>
    func getProducts() async -> Result<GetProductsResponse, APIServiceError>
    func getCustomerPortalURL(accessToken: String, externalID: String) async -> Result<GetCustomerPortalURLResponse, APIServiceError>
    func confirmPurchase(accessToken: String, signature: String) async -> Result<ConfirmPurchaseResponse, APIServiceError>
}

public typealias GetSubscriptionResponse = Subscription

public enum CachePolicy {
    case reloadIgnoringLocalCacheData
    case returnCacheDataElseLoad
    case returnCacheDataDontLoad
}

public enum SubscriptionServiceError: Error {
    case noCachedData
    case apiError(APIServiceError)
}

public typealias GetProductsResponse = [GetProductsItem]

public struct GetProductsItem: Decodable {
    public let productId: String
    public let productLabel: String
    public let billingPeriod: String
    public let price: String
    public let currency: String
}

public struct GetCustomerPortalURLResponse: Decodable {
    public let customerPortalUrl: String
}

public struct ConfirmPurchaseResponse: Decodable {
    public let email: String?
    public let entitlements: [Entitlement]
    public let subscription: Subscription
}

// MARK: - Implementation

public final class SubscriptionService: APIService, SubscriptionServiceProtocol {

    let environment: SubscriptionServiceEnvironment

    public var baseURL: URL {
        switch environment {
        case .production:
            URL(string: "https://subscriptions.duckduckgo.com/api")!
        case .staging:
            URL(string: "https://subscriptions-dev.duckduckgo.com/api")!
        }
    }

    public let session = {
        let configuration = URLSessionConfiguration.ephemeral
        return URLSession(configuration: configuration)
    }()

    init(environment: SubscriptionServiceEnvironment) {
        self.environment = environment
        print("-- SubscriptionService init")
    }

    deinit {
        print("-- SubscriptionService deinit")
    }

    // MARK: - Cache

    private static let subscriptionCache = UserDefaultsCache<Subscription>(key: UserDefaultsCacheKey.subscription)

    // MARK: - Subscription fetching with caching

    private func getRemoteSubscription(accessToken: String) async -> Result<Subscription, SubscriptionServiceError> {
        print("-- SubscriptionService getRemoteSubscription")
        let result: Result<GetSubscriptionResponse, APIServiceError> = await executeAPICall(method: "GET", endpoint: "subscription", headers: makeAuthorizationHeader(for: accessToken))

        print("-- SubscriptionService getRemoteSubscription after call")
        switch result {
        case .success(let subscriptionResponse):
            Self.subscriptionCache.set(subscriptionResponse)
            return .success(subscriptionResponse)
        case .failure(let error):
            return .failure(.apiError(error))
        }

    }

    public func getSubscription(accessToken: String) async -> Result<Subscription, SubscriptionServiceError> {
        await getSubscription(accessToken: accessToken, cachePolicy: .returnCacheDataElseLoad)
    }

    public func getSubscription(accessToken: String, cachePolicy: CachePolicy) async -> Result<Subscription, SubscriptionServiceError> {

        switch cachePolicy {
        case .reloadIgnoringLocalCacheData:
            return await getRemoteSubscription(accessToken: accessToken)

        case .returnCacheDataElseLoad:
            if let cachedSubscription = Self.subscriptionCache.get() {
                return .success(cachedSubscription)
            } else {
                return await getRemoteSubscription(accessToken: accessToken)
            }

        case .returnCacheDataDontLoad:
            if let cachedSubscription = Self.subscriptionCache.get() {
                return .success(cachedSubscription)
            } else {
                return .failure(.noCachedData)
            }
        }
    }

    public static func signOut() {
        subscriptionCache.reset()
    }

    public typealias GetSubscriptionResponse = Subscription

    // MARK: -

    public func getProducts() async -> Result<GetProductsResponse, APIServiceError> {
        await executeAPICall(method: "GET", endpoint: "products")
    }

    // MARK: -

    public func getCustomerPortalURL(accessToken: String, externalID: String) async -> Result<GetCustomerPortalURLResponse, APIServiceError> {
        var headers = makeAuthorizationHeader(for: accessToken)
        headers["externalAccountId"] = externalID
        return await executeAPICall(method: "GET", endpoint: "checkout/portal", headers: headers)
    }

    // MARK: -

    public func confirmPurchase(accessToken: String, signature: String) async -> Result<ConfirmPurchaseResponse, APIServiceError> {
        let headers = makeAuthorizationHeader(for: accessToken)
        let bodyDict = ["signedTransactionInfo": signature]

        guard let bodyData = try? JSONEncoder().encode(bodyDict) else { return .failure(.encodingError) }
        return await executeAPICall(method: "POST", endpoint: "purchase/confirm/apple", headers: headers, body: bodyData)
    }
}
