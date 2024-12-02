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
import Networking
import os.log

public struct GetProductsItem: Codable, Equatable {
    public let productId: String
    public let productLabel: String
    public let billingPeriod: String
    public let price: String
    public let currency: String
}

public struct GetCustomerPortalURLResponse: Codable, Equatable {
    public let customerPortalUrl: String
}

public struct ConfirmPurchaseResponse: Codable, Equatable {
    public let email: String?
    public let subscription: PrivacyProSubscription
}

public struct GetSubscriptionFeaturesResponse: Decodable {
    public let features: [SubscriptionEntitlement]
}

public enum SubscriptionEndpointServiceError: Error {
    case noData
    case invalidRequest
    case invalidResponseCode(HTTPStatusCode)
}

public enum SubscriptionCachePolicy {
    case reloadIgnoringLocalCacheData
    case returnCacheDataElseLoad
    case returnCacheDataDontLoad
}

public protocol SubscriptionEndpointService {
    func updateCache(with subscription: PrivacyProSubscription)
    func getSubscription(accessToken: String, cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription
    func clearSubscription()
    func getProducts() async throws -> [GetProductsItem]
    func getSubscriptionFeatures(for subscriptionID: String) async throws -> GetSubscriptionFeaturesResponse
    func getCustomerPortalURL(accessToken: String, externalID: String) async throws -> GetCustomerPortalURLResponse
    func confirmPurchase(accessToken: String, signature: String) async throws -> ConfirmPurchaseResponse
}

extension SubscriptionEndpointService {

    public func getSubscription(accessToken: String) async throws -> PrivacyProSubscription {
        try await getSubscription(accessToken: accessToken, cachePolicy: SubscriptionCachePolicy.returnCacheDataElseLoad)
    }
}

/// Communicates with our backend
public struct DefaultSubscriptionEndpointService: SubscriptionEndpointService {

    private let apiService: APIService
    private let baseURL: URL
    private let subscriptionCache: UserDefaultsCache<PrivacyProSubscription>

    public init(apiService: APIService,
                baseURL: URL,
                subscriptionCache: UserDefaultsCache<PrivacyProSubscription> = UserDefaultsCache<PrivacyProSubscription>(key: UserDefaultsCacheKey.subscription, settings: UserDefaultsCacheSettings(defaultExpirationInterval: .minutes(20)))) {
        self.apiService = apiService
        self.baseURL = baseURL
        self.subscriptionCache = subscriptionCache
    }

    // MARK: - Subscription fetching with caching

    enum GetSubscriptionError: String, Decodable {
        case noData = ""
    }

    private func getRemoteSubscription(accessToken: String) async throws -> PrivacyProSubscription {

        Logger.subscriptionEndpointService.log("Requesting subscription details")
        guard let request = SubscriptionRequest.getSubscription(baseURL: baseURL, accessToken: accessToken) else {
            throw SubscriptionEndpointServiceError.invalidRequest
        }
        let response = try await apiService.fetch(request: request.apiRequest)
        let statusCode = response.httpResponse.httpStatus

        if statusCode.isSuccess {
            let subscription: PrivacyProSubscription = try response.decodeBody()
            updateCache(with: subscription)
            Logger.subscriptionEndpointService.log("Subscription details retrieved successfully: \(String(describing: subscription))")
            return subscription
        } else {
            guard statusCode == .badRequest,
                  let error: GetSubscriptionError = try response.decodeBody(),
                  error == .noData else {
                let bodyString: String = try response.decodeBody()
                Logger.subscriptionEndpointService.log("Failed to retrieve Subscription details: \(bodyString)")
                throw SubscriptionEndpointServiceError.invalidResponseCode(statusCode)
            }

            Logger.subscriptionEndpointService.log("No subscription found")
            subscriptionCache.reset()
            throw SubscriptionEndpointServiceError.noData
        }
    }

    public func updateCache(with subscription: PrivacyProSubscription) {
        subscriptionCache.set(subscription)
        NotificationCenter.default.post(name: .subscriptionDidChange, object: self, userInfo: [UserDefaultsCacheKey.subscription: subscription])
    }

    public func getSubscription(accessToken: String, cachePolicy: SubscriptionCachePolicy = .returnCacheDataElseLoad) async throws -> PrivacyProSubscription {

        switch cachePolicy {
        case .reloadIgnoringLocalCacheData:
            return try await getRemoteSubscription(accessToken: accessToken)

        case .returnCacheDataElseLoad:
            if let cachedSubscription = subscriptionCache.get() {
                return cachedSubscription
            } else {
                return try await getRemoteSubscription(accessToken: accessToken)
            }

        case .returnCacheDataDontLoad:
            if let cachedSubscription = subscriptionCache.get() {
                return cachedSubscription
            } else {
                throw SubscriptionEndpointServiceError.noData
            }
        }
    }

    public func clearSubscription() {
        subscriptionCache.reset()
    }

    // MARK: -

    public func getProducts() async throws -> [GetProductsItem] {
        // await apiService.executeAPICall(method: "GET", endpoint: "products", headers: nil, body: nil)
        guard let request = SubscriptionRequest.getProducts(baseURL: baseURL) else {
            throw SubscriptionEndpointServiceError.invalidRequest
        }
        let response = try await apiService.fetch(request: request.apiRequest)
        let statusCode = response.httpResponse.httpStatus

        if statusCode.isSuccess {
            Logger.subscriptionEndpointService.log("\(#function) request completed")
            return try response.decodeBody()
        } else {
            throw SubscriptionEndpointServiceError.invalidResponseCode(statusCode)
        }
    }

    // MARK: -

    public func getCustomerPortalURL(accessToken: String, externalID: String) async throws -> GetCustomerPortalURLResponse {
        guard let request = SubscriptionRequest.getCustomerPortalURL(baseURL: baseURL, accessToken: accessToken, externalID: externalID) else {
            throw SubscriptionEndpointServiceError.invalidRequest
        }
        let response = try await apiService.fetch(request: request.apiRequest)
        let statusCode = response.httpResponse.httpStatus
        if statusCode.isSuccess {
            Logger.subscriptionEndpointService.log("\(#function) request completed")
            return try response.decodeBody()
        } else {
            throw SubscriptionEndpointServiceError.invalidResponseCode(statusCode)
        }
    }

    // MARK: -

    public func confirmPurchase(accessToken: String, signature: String) async throws -> ConfirmPurchaseResponse {
        Logger.subscriptionEndpointService.log("Confirming purchase")
        guard let request = SubscriptionRequest.confirmPurchase(baseURL: baseURL, accessToken: accessToken, signature: signature) else {
            throw SubscriptionEndpointServiceError.invalidRequest
        }
        let response = try await apiService.fetch(request: request.apiRequest)
        let statusCode = response.httpResponse.httpStatus
        if statusCode.isSuccess {
            Logger.subscriptionEndpointService.log("\(#function) request completed")
            return try response.decodeBody()
        } else {
            throw SubscriptionEndpointServiceError.invalidResponseCode(statusCode)
        }
    }

    public func getSubscriptionFeatures(for subscriptionID: String) async throws -> GetSubscriptionFeaturesResponse {
        Logger.subscriptionEndpointService.log("Getting subscription features")
        guard let request = SubscriptionRequest.subscriptionFeatures(baseURL: baseURL, subscriptionID: subscriptionID) else {
            throw SubscriptionEndpointServiceError.invalidRequest
        }
        let response = try await apiService.fetch(request: request.apiRequest)
        let statusCode = response.httpResponse.httpStatus
        if statusCode.isSuccess {
            Logger.subscriptionEndpointService.log("\(#function) request completed")
            return try response.decodeBody()
        } else {
            throw SubscriptionEndpointServiceError.invalidResponseCode(statusCode)
        }
    }
}
