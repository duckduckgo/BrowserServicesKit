//
//  StorePurchaseManagerMock.swift
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

public class StorePurchaseManagerMock: StorePurchaseManager {
    public var purchasedProductIDs: [String]
    public var purchaseQueue: [String]
    public var areProductsAvailable: Bool
    public var subscriptionOptionsResult: SubscriptionOptions?
    public var syncAppleIDAccountResultError: Error?

    public var onMostRecentTransaction: (() -> String?)?
    public var onHasActiveSubscription: (() -> Bool)?
    public var onPurchaseSubscription: ((String, String) -> Result<TransactionJWS, StorePurchaseManagerError>)?

    public var purchaseSubscriptionCalled: Bool = false

    public init(purchasedProductIDs: [String] = [],
                purchaseQueue: [String] = [],
                areProductsAvailable: Bool = false,
                subscriptionOptionsResult: SubscriptionOptions? = nil,
                syncAppleIDAccountResultError: Error? = nil) {
        self.purchasedProductIDs = purchasedProductIDs
        self.purchaseQueue = purchaseQueue
        self.areProductsAvailable = areProductsAvailable
        self.subscriptionOptionsResult = subscriptionOptionsResult
        self.syncAppleIDAccountResultError = syncAppleIDAccountResultError
    }

    public func subscriptionOptions() async -> SubscriptionOptions? {
        subscriptionOptionsResult
    }

    public func syncAppleIDAccount() async throws {
        if let syncAppleIDAccountResultError {
            throw syncAppleIDAccountResultError
        }
    }

    public func updateAvailableProducts() async { }

    public func updatePurchasedProducts() async { }

    public func mostRecentTransaction() async -> String? {
        onMostRecentTransaction!()
    }

    public func hasActiveSubscription() async -> Bool {
        onHasActiveSubscription!()
    }

    public func purchaseSubscription(with identifier: String, externalID: String) async -> Result<TransactionJWS, StorePurchaseManagerError> {
        purchaseSubscriptionCalled = true
        return onPurchaseSubscription!(identifier, externalID)
    }
}
