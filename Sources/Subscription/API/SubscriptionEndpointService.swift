//
//  SubscriptionEndpointService.swift
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

public enum SubscriptionServiceError: Error {
    case noCachedData
    case apiError(APIServiceError)
}

public protocol SubscriptionEndpointService {
    func updateCache(with subscription: Subscription)
    func getSubscription(accessToken: String, cachePolicy: APICachePolicy) async -> Result<Subscription, SubscriptionServiceError>
    func signOut()
    func getProducts() async -> Result<[GetProductsItem], APIServiceError>
    func getCustomerPortalURL(accessToken: String, externalID: String) async -> Result<GetCustomerPortalURLResponse, APIServiceError>
    func confirmPurchase(accessToken: String, signature: String) async -> Result<ConfirmPurchaseResponse, APIServiceError>
}

extension SubscriptionEndpointService {

    public func getSubscription(accessToken: String) async -> Result<Subscription, SubscriptionServiceError> {
        await getSubscription(accessToken: accessToken, cachePolicy: .returnCacheDataElseLoad)
    }
}

/// Communicates with our backend
public struct DefaultSubscriptionEndpointService: SubscriptionEndpointService {
    private let currentServiceEnvironment: SubscriptionEnvironment.ServiceEnvironment
    private let apiService: APIService
    private let subscriptionCache = UserDefaultsCache<Subscription>(key: UserDefaultsCacheKey.subscription,
                                                                    settings: UserDefaultsCacheSettings(defaultExpirationInterval: .minutes(20)))

    public init(currentServiceEnvironment: SubscriptionEnvironment.ServiceEnvironment, apiService: APIService) {
        self.currentServiceEnvironment = currentServiceEnvironment
        self.apiService = apiService
    }

    // MARK: - Subscription fetching with caching

    private func getRemoteSubscription(accessToken: String) async -> Result<Subscription, SubscriptionServiceError> {

        let result: Result<Subscription, APIServiceError> = await apiService.executeAPICall(method: "GET", endpoint: "subscription", headers: apiService.makeAuthorizationHeader(for: accessToken), body: nil)
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

    public func getSubscription(accessToken: String, cachePolicy: APICachePolicy = .returnCacheDataElseLoad) async -> Result<Subscription, SubscriptionServiceError> {

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
        await apiService.executeAPICall(method: "GET", endpoint: "products", headers: nil, body: nil)
    }

    // MARK: -

    public func getCustomerPortalURL(accessToken: String, externalID: String) async -> Result<GetCustomerPortalURLResponse, APIServiceError> {
        var headers = apiService.makeAuthorizationHeader(for: accessToken)
        headers["externalAccountId"] = externalID
        return await apiService.executeAPICall(method: "GET", endpoint: "checkout/portal", headers: headers, body: nil)
    }

    // MARK: -

    public func confirmPurchase(accessToken: String, signature: String) async -> Result<ConfirmPurchaseResponse, APIServiceError> {
        let headers = apiService.makeAuthorizationHeader(for: accessToken)
        let bodyDict = ["signedTransactionInfo": signature]

        guard let bodyData = try? JSONEncoder().encode(bodyDict) else { return .failure(.encodingError) }
        return await apiService.executeAPICall(method: "POST", endpoint: "purchase/confirm/apple", headers: headers, body: bodyData)
    }
}

extension DefaultSubscriptionEndpointService {

    public init(currentServiceEnvironment: SubscriptionEnvironment.ServiceEnvironment) {
        self.currentServiceEnvironment = currentServiceEnvironment
        let baseURL = currentServiceEnvironment == .production ? URL(string: "https://subscriptions.duckduckgo.com/api")! : URL(string: "https://subscriptions-dev.duckduckgo.com/api")!
        let session = URLSession(configuration: URLSessionConfiguration.ephemeral)
        self.apiService = DefaultAPIService(baseURL: baseURL, session: session)
    }
}
