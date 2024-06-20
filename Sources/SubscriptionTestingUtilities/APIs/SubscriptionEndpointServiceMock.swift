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

public struct SubscriptionEndpointServiceMock: SubscriptionEndpointService {

    let getSubscriptionResult: Result<Subscription, SubscriptionServiceError>
    let getProductsResult: Result<[GetProductsItem], APIServiceError>
    let getCustomerPortalURLResult: Result<GetCustomerPortalURLResponse, APIServiceError>
    let confirmPurchaseResult: Result<ConfirmPurchaseResponse, APIServiceError>

    public func updateCache(with subscription: Subscription) {

    }

    public func getSubscription(accessToken: String, cachePolicy: APICachePolicy) async -> Result<Subscription, SubscriptionServiceError> {
        getSubscriptionResult
    }

    public func signOut() {

    }

    public func getProducts() async -> Result<[GetProductsItem], APIServiceError> {
        getProductsResult
    }

    public func getCustomerPortalURL(accessToken: String, externalID: String) async -> Result<GetCustomerPortalURLResponse, APIServiceError> {
        getCustomerPortalURLResult
    }

    public func confirmPurchase(accessToken: String, signature: String) async -> Result<ConfirmPurchaseResponse, APIServiceError> {
        confirmPurchaseResult
    }
}
