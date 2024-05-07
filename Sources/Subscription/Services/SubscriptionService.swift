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

/// Communicates with our backend
public final class SubscriptionService: APIService {

    let currentServiceEnvironment: SubscriptionEnvironment.ServiceEnvironment

    public init(currentServiceEnvironment: SubscriptionEnvironment.ServiceEnvironment) {
        self.currentServiceEnvironment = currentServiceEnvironment
    }

    public let session = {
        let configuration = URLSessionConfiguration.ephemeral
        return URLSession(configuration: configuration)
    }()

    public var baseURL: URL {
        switch currentServiceEnvironment {
        case .production:
            URL(string: "https://subscriptions.duckduckgo.com/api")!
        case .staging:
            URL(string: "https://subscriptions-dev.duckduckgo.com/api")!
        }
    }

    private let subscriptionCache = UserDefaultsCache<Subscription>(key: UserDefaultsCacheKey.subscription,
                                                                    settings: UserDefaultsCacheSettings(defaultExpirationInterval: .minutes(20)))

    public enum CachePolicy {
        case reloadIgnoringLocalCacheData
        case returnCacheDataElseLoad
        case returnCacheDataDontLoad
    }

    public enum SubscriptionServiceError: Error {
        case noCachedData
        case apiError(APIServiceError)
    }

    // MARK: - Subscription fetching with caching

    private func getRemoteSubscription(accessToken: String) async -> Result<Subscription, SubscriptionServiceError> {

        let result: Result<Subscription, APIServiceError> = await executeAPICall(method: "GET", endpoint: "subscription", headers: makeAuthorizationHeader(for: accessToken))
        switch result {
        case .success(let subscriptionResponse):
            updateCache(with: subscriptionResponse)
            return .success(subscriptionResponse)
        case .failure(let error):
            return .failure(.apiError(error))
        }
    }

    public func updateCache(with subscription: Subscription) {

        let cachedSubscription: Subscription? = subscriptionCache.get()
        if subscription != cachedSubscription {
            let defaultExpiryDate = Date().addingTimeInterval(subscriptionCache.settings.defaultExpirationInterval)
            let expiryDate = min(defaultExpiryDate, subscription.expiresOrRenewsAt)

            subscriptionCache.set(subscription, expires: expiryDate)
            NotificationCenter.default.post(name: .subscriptionDidChange, object: self, userInfo: [UserDefaultsCacheKey.subscription: subscription])
        }
    }

    public func getSubscription(accessToken: String, cachePolicy: CachePolicy = .returnCacheDataElseLoad) async -> Result<Subscription, SubscriptionServiceError> {

        switch cachePolicy {
        case .reloadIgnoringLocalCacheData:
            return await getRemoteSubscription(accessToken: accessToken)

        case .returnCacheDataElseLoad:
            if let cachedSubscription = subscriptionCache.get() {
                return .success(cachedSubscription)
            } else {
                return await getRemoteSubscription(accessToken: accessToken)
            }

        case .returnCacheDataDontLoad:
            if let cachedSubscription = subscriptionCache.get() {
                return .success(cachedSubscription)
            } else {
                return .failure(.noCachedData)
            }
        }
    }

    public func signOut() {
        subscriptionCache.reset()
    }

    // MARK: -

    public func getProducts() async -> Result<[GetProductsItem], APIServiceError> {
        await executeAPICall(method: "GET", endpoint: "products")
    }

    public struct GetProductsItem: Decodable {
        public let productId: String
        public let productLabel: String
        public let billingPeriod: String
        public let price: String
        public let currency: String
    }

    // MARK: -

    public func getCustomerPortalURL(accessToken: String, externalID: String) async -> Result<GetCustomerPortalURLResponse, APIServiceError> {
        var headers = makeAuthorizationHeader(for: accessToken)
        headers["externalAccountId"] = externalID
        return await executeAPICall(method: "GET", endpoint: "checkout/portal", headers: headers)
    }

    public struct GetCustomerPortalURLResponse: Decodable {
        public let customerPortalUrl: String
    }

    // MARK: -

    public func confirmPurchase(accessToken: String, signature: String) async -> Result<ConfirmPurchaseResponse, APIServiceError> {
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
