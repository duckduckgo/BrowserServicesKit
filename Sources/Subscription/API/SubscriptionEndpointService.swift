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
    /*
     {
         "email": "",
         "entitlements": [
             {
                 "product": "Data Broker Protection",
                 "name": "subscriber"
             },
             {
                 "product": "Identity Theft Restoration",
                 "name": "subscriber"
             },
             {
                 "product": "Network Protection",
                 "name": "subscriber"
             }
         ],
         "subscription": {
             "productId": "ios.subscription.1month",
             "name": "Monthly Subscription",
             "billingPeriod": "Monthly",
             "startedAt": 1729784648000,
             "expiresOrRenewsAt": 1729784948000,
             "platform": "apple",
             "status": "Auto-Renewable"
         }
     }
     */
    public let email: String?
//    public let entitlements: [Entitlement]
    public let subscription: PrivacyProSubscription
}

//public struct Entitlement: Codable, Equatable {
//    public let product: ProductName
//
//    public enum ProductName: String, Codable {
//        case networkProtection = "Network Protection"
//        case dataBrokerProtection = "Data Broker Protection"
//        case identityTheftRestoration = "Identity Theft Restoration"
//        case unknown
//
//        public init(from decoder: Decoder) throws {
//            self = try Self(rawValue: decoder.singleValueContainer().decode(RawValue.self)) ?? .unknown
//        }
//    }
//}

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

//    private let currentServiceEnvironment: SubscriptionEnvironment.ServiceEnvironment
    private let apiService: APIService
    private let baseURL: URL
    private let subscriptionCache = UserDefaultsCache<PrivacyProSubscription>(key: UserDefaultsCacheKey.subscription, settings: UserDefaultsCacheSettings(defaultExpirationInterval: .minutes(20)))

    public init(apiService: APIService, baseURL: URL) {
//        self.currentServiceEnvironment = currentServiceEnvironment
        self.apiService = apiService
        self.baseURL = baseURL
    }

//    public init(currentServiceEnvironment: SubscriptionEnvironment.ServiceEnvironment) {
////        self.currentServiceEnvironment = currentServiceEnvironment
//        let session = URLSession(configuration: URLSessionConfiguration.ephemeral)
//        self.apiService = DefaultAPIService(baseURL: currentServiceEnvironment.url, session: session)
//    }

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
            updateCache(with: subscription)
            Logger.subscriptionEndpointService.log("Subscription details retrieved successfully: \(String(describing: subscription))")
            return subscription
        } else {
            let error: String = try response.decodeBody()
            Logger.subscriptionEndpointService.log("Failed to retrieve Subscription details: \(error)")
            throw SubscriptionEndpointServiceError.invalidResponseCode(statusCode)
        }
        
//        let result: Result<Subscription, APIServiceError> = await apiService.executeAPICall(method: "GET", endpoint: "subscription", headers: apiService.makeAuthorizationHeader(for: accessToken), body: nil)
//        switch result {
//        case .success(let subscriptionResponse):
//            updateCache(with: subscriptionResponse)
//            return .success(subscriptionResponse)
//        case .failure(let error):
//            return .failure(.apiError(error))
//        }
    }

    public func updateCache(with subscription: PrivacyProSubscription) { // TODO: why all this overhead? just replace and notify, TBC
//        let cachedSubscription: PrivacyProSubscription? = subscriptionCache.get()
//        if subscription != cachedSubscription {
//            let defaultExpiryDate = Date().addingTimeInterval(subscriptionCache.settings.defaultExpirationInterval)
//            let expiryDate = min(defaultExpiryDate, subscription.expiresOrRenewsAt)
//
//            subscriptionCache.set(subscription, expires: expiryDate)
//            NotificationCenter.default.post(name: .subscriptionDidChange, object: self, userInfo: [UserDefaultsCacheKey.subscription: subscription])
//        }
        subscriptionCache.set(subscription)
        NotificationCenter.default.post(name: .subscriptionDidChange, object: self, userInfo: [UserDefaultsCacheKey.subscription: subscription])
    }

    public func getSubscription(accessToken: String, cachePolicy: SubscriptionCachePolicy = .returnCacheDataElseLoad) async throws -> PrivacyProSubscription {

        switch cachePolicy { // TODO: improve removing code duplication
        case .reloadIgnoringLocalCacheData:
            if let subscription = try? await getRemoteSubscription(accessToken: accessToken) {
                subscriptionCache.set(subscription)
                return subscription
            } else {
                throw SubscriptionEndpointServiceError.noData
            }

        case .returnCacheDataElseLoad:
            if let cachedSubscription = subscriptionCache.get() {
                return cachedSubscription
            } else {
                if let subscription = try? await getRemoteSubscription(accessToken: accessToken) {
                    subscriptionCache.set(subscription)
                    return subscription
                } else {
                    throw SubscriptionEndpointServiceError.noData
                }
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
        //await apiService.executeAPICall(method: "GET", endpoint: "products", headers: nil, body: nil)
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
//        var headers = apiService.makeAuthorizationHeader(for: accessToken)
//        headers["externalAccountId"] = externalID
//        return await apiService.executeAPICall(method: "GET", endpoint: "checkout/portal", headers: headers, body: nil)
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
}
