//
//  SubscriptionEndpointServiceV2.swift
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

public struct ConfirmPurchaseResponseV2: Codable, Equatable {
    public let email: String?
    public let subscription: PrivacyProSubscription
}

public struct GetSubscriptionFeaturesResponseV2: Decodable {
    public let features: [SubscriptionEntitlement]
}

public enum SubscriptionEndpointServiceError: Error, Equatable {
    case noData
    case invalidRequest
    case invalidResponseCode(HTTPStatusCode)
}

public enum SubscriptionCachePolicy {
    case reloadIgnoringLocalCacheData
    case returnCacheDataElseLoad
    case returnCacheDataDontLoad
}

public protocol SubscriptionEndpointServiceV2 {
    func ingestSubscription(_ subscription: PrivacyProSubscription) async throws
    func getSubscription(accessToken: String, cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription
    func clearSubscription()
    func getProducts() async throws -> [GetProductsItem]
    func getSubscriptionFeatures(for subscriptionID: String) async throws -> GetSubscriptionFeaturesResponseV2
    func getCustomerPortalURL(accessToken: String, externalID: String) async throws -> GetCustomerPortalURLResponse

    /// Confirms a subscription purchase by validating the provided access token and signature with the backend service.
    ///
    /// This method sends the necessary data to the server to confirm the purchase,
    /// and optionally includes additional parameters for customization.
    ///
    /// - Parameters:
    ///   - accessToken: A string representing the user's access token, used for authentication.
    ///   - signature: A string representing the purchase signature.
    ///   - additionalParams: An optional dictionary of additional parameters to include in the request.
    /// - Returns: A `ConfirmPurchaseResponse` object on success
    func confirmPurchase(accessToken: String, signature: String, additionalParams: [String: String]?) async throws -> ConfirmPurchaseResponseV2
}

extension SubscriptionEndpointServiceV2 {

    public func getSubscription(accessToken: String) async throws -> PrivacyProSubscription {
        try await getSubscription(accessToken: accessToken, cachePolicy: SubscriptionCachePolicy.returnCacheDataElseLoad)
    }
}

/// Communicates with our backend
public struct DefaultSubscriptionEndpointServiceV2: SubscriptionEndpointServiceV2 {

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

    private func getRemoteSubscription(accessToken: String) async throws -> PrivacyProSubscription {

        Logger.subscriptionEndpointService.log("Requesting subscription details")
        guard let request = SubscriptionRequest.getSubscription(baseURL: baseURL, accessToken: accessToken) else {
            throw SubscriptionEndpointServiceError.invalidRequest
        }
        let response = try await apiService.fetch(request: request.apiRequest)
        let statusCode = response.httpResponse.httpStatus

        if statusCode.isSuccess {
            let subscription: PrivacyProSubscription = try response.decodeBody()
            Logger.subscriptionEndpointService.log("Subscription details retrieved successfully: \(subscription.debugDescription, privacy: .public)")
            return try await storeAndAddFeaturesIfNeededTo(subscription: subscription)
        } else {
            if statusCode == .badRequest {
                Logger.subscriptionEndpointService.log("No subscription found")
                clearSubscription()
                throw SubscriptionEndpointServiceError.noData
            } else {
                let bodyString: String = try response.decodeBody()
                Logger.subscriptionEndpointService.log("(\(statusCode.description) Failed to retrieve Subscription details: \(bodyString)")
                throw SubscriptionEndpointServiceError.invalidResponseCode(statusCode)
            }
        }
    }

    @discardableResult
    private func storeAndAddFeaturesIfNeededTo(subscription: PrivacyProSubscription) async throws -> PrivacyProSubscription {
        let cachedSubscription: PrivacyProSubscription? = subscriptionCache.get()
        var subscription = subscription
        // fetch remote features
        Logger.subscriptionEndpointService.log("Getting features for subscription: \(subscription.productId, privacy: .public)")
        subscription.features = try await getSubscriptionFeatures(for: subscription.productId).features
        Logger.subscriptionEndpointService.debug("""
Subscription:
Cached: \(cachedSubscription?.debugDescription ?? "nil", privacy: .public)
New: \(subscription.debugDescription, privacy: .public)
""")
        if subscription != cachedSubscription {
            updateCache(with: subscription)
        } else {
            Logger.subscriptionEndpointService.debug("No subscription update required")
        }
        return subscription
    }

    func updateCache(with subscription: PrivacyProSubscription) {
        cacheSerialQueue.sync {
            subscriptionCache.set(subscription)
            Logger.subscriptionEndpointService.debug("Notifying subscription changed")
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
// TODO: check if needed: NotificationCenter.default.post(name: .subscriptionDidChange, object: self, userInfo: nil)
    }

    // MARK: -

    public func getProducts() async throws -> [GetProductsItem] {
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

    public func confirmPurchase(accessToken: String, signature: String, additionalParams: [String: String]?) async throws -> ConfirmPurchaseResponseV2 {
        guard let request = SubscriptionRequest.confirmPurchase(baseURL: baseURL,
                                                                accessToken: accessToken,
                                                                signature: signature,
                                                                additionalParams: additionalParams) else {
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

    public func getSubscriptionFeatures(for subscriptionID: String) async throws -> GetSubscriptionFeaturesResponseV2 {
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
