//
//  SubscriptionEndpointServiceMock.swift
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

import Foundation
import Subscription
import Networking

public final class SubscriptionEndpointServiceMock: SubscriptionEndpointService {
    public var getSubscriptionResult: Result<PrivacyProSubscription, SubscriptionServiceError>?
    public var getProductsResult: Result<[GetProductsItem], APIRequestV2.Error>?
    public var getCustomerPortalURLResult: Result<GetCustomerPortalURLResponse, APIRequestV2.Error>?
    public var confirmPurchaseResult: Result<ConfirmPurchaseResponse, APIRequestV2.Error>?

    public var onUpdateCache: ((PrivacyProSubscription) -> Void)?
    public var onGetSubscription: ((String, SubscriptionCachePolicy) -> Void)?
    public var onSignOut: (() -> Void)?

    public var updateCacheWithSubscriptionCalled: Bool = false
    public var getSubscriptionCalled: Bool = false
    public var signOutCalled: Bool = false

    public init() { }

    public func updateCache(with subscription: PrivacyProSubscription) {
        onUpdateCache?(subscription)
        updateCacheWithSubscriptionCalled = true
    }

    public func getSubscription(accessToken: String, cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription {
        getSubscriptionCalled = true
        onGetSubscription?(accessToken, cachePolicy)
        switch getSubscriptionResult! {
            case .success(let subscription): return subscription
            case .failure(let error): throw error
        }
    }

    public func signOut() {
        signOutCalled = true
        onSignOut?()
    }

    public func getProducts() async throws -> [GetProductsItem] {
        switch getProductsResult! {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    public func getCustomerPortalURL(accessToken: String, externalID: String) async throws -> GetCustomerPortalURLResponse {
        switch getCustomerPortalURLResult! {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    public func confirmPurchase(accessToken: String, signature: String) async throws -> ConfirmPurchaseResponse {
        switch confirmPurchaseResult! {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }
}
