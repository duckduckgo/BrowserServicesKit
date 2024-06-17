//
//  AppStorePurchaseFlowMock.swift
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
@testable import Subscription

public class AppStorePurchaseFlowMock: AppStorePurchaseFlowing {

    var purchaseSubscriptionResult: Result<TransactionJWS, AppStorePurchaseFlowError>
    var completeSubscriptionPurchaseResult: Result<PurchaseUpdate, AppStorePurchaseFlowError>

    public init(purchaseSubscriptionResult: Result<TransactionJWS, AppStorePurchaseFlowError>, completeSubscriptionPurchaseResult: Result<PurchaseUpdate, AppStorePurchaseFlowError>) {
        self.purchaseSubscriptionResult = purchaseSubscriptionResult
        self.completeSubscriptionPurchaseResult = completeSubscriptionPurchaseResult
    }

    public func purchaseSubscription(with subscriptionIdentifier: String, emailAccessToken: String?) async -> Result<TransactionJWS, AppStorePurchaseFlowError> {
        purchaseSubscriptionResult
    }
    
    public func completeSubscriptionPurchase(with transactionJWS: TransactionJWS) async -> Result<PurchaseUpdate, AppStorePurchaseFlowError> {
        completeSubscriptionPurchaseResult
    }
}
