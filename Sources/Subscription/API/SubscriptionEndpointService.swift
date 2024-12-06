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
    func ingestSubscription(_ subscription: PrivacyProSubscription) async throws
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
    private let cacheSerialQueue = DispatchQueue(label: "com.duckduckgo.subscriptionEndpointService.cache", qos: .background)

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
            Logger.subscriptionEndpointService.log("Subscription details retrieved successfully: \(String(describing: subscription))")

            try await storeAndAddFeaturesIfNeededTo(subscription: subscription)

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
            clearSubscription()
            throw SubscriptionEndpointServiceError.noData
        }
    }

    private func storeAndAddFeaturesIfNeededTo(subscription: PrivacyProSubscription) async throws {
        let cachedSubscription: PrivacyProSubscription? = subscriptionCache.get()
        if subscription != cachedSubscription {
            var subscription = subscription
            // fetch remote features
            subscription.features = try await getSubscriptionFeatures(for: subscription.productId).features

            updateCache(with: subscription)

            Logger.subscriptionEndpointService.debug("""
Subscription changed, updating cache and notifying observers.
Old: \(cachedSubscription?.debugDescription ?? "nil")
New: \(subscription.debugDescription)
""")
        } else {
            Logger.subscriptionEndpointService.debug("No subscription update required")
        }
    }

    func updateCache(with subscription: PrivacyProSubscription) {
        cacheSerialQueue.sync {
            subscriptionCache.set(subscription)
            NotificationCenter.default.post(name: .subscriptionDidChange, object: self, userInfo: [UserDefaultsCacheKey.subscription: subscription])
        }
    }

    public func ingestSubscription(_ subscription: PrivacyProSubscription) async throws {
        try await storeAndAddFeaturesIfNeededTo(subscription: subscription)
    }

    public func getSubscription(accessToken: String, cachePolicy: SubscriptionCachePolicy = .returnCacheDataElseLoad) async throws -> PrivacyProSubscription {
        switch cachePolicy {
        case .reloadIgnoringLocalCacheData:
            return try await getRemoteSubscription(accessToken: accessToken)

        case .returnCacheDataElseLoad:
            if let cachedSubscription = getCachedSubscription() {
                return cachedSubscription
            } else {
                return try await getRemoteSubscription(accessToken: accessToken)
            }

        case .returnCacheDataDontLoad:
            if let cachedSubscription = getCachedSubscription() {
                return cachedSubscription
            } else {
                throw SubscriptionEndpointServiceError.noData
            }
        }
    }

    private func getCachedSubscription() -> PrivacyProSubscription? {
        var result: PrivacyProSubscription?
        cacheSerialQueue.sync {
            result = subscriptionCache.get()
        }
        return result
    }

    public func clearSubscription() {
        cacheSerialQueue.sync {
            subscriptionCache.reset()
        }
//        NotificationCenter.default.post(name: .subscriptionDidChange, object: self, userInfo: nil)
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
