//
//  StorePurchaseManaging.swift
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

public enum StoreError: Error {
    case failedVerification
}

public enum PurchaseManagerError: Error {
    case productNotFound
    case externalIDisNotAValidUUID
    case purchaseFailed
    case transactionCannotBeVerified
    case transactionPendingAuthentication
    case purchaseCancelledByUser
    case unknownError
}

public protocol StorePurchaseManaging {

    func subscriptionOptions() async -> SubscriptionOptions?

    var purchasedProductIDs: [String] { get }

    var purchaseQueue: [String] { get }

    var areProductsAvailable: Bool { get }

    @discardableResult @MainActor func syncAppleIDAccount() async -> Result<Void, Error>

    @MainActor func updateAvailableProducts() async

    @MainActor func updatePurchasedProducts() async

    @MainActor func mostRecentTransaction() async -> String?

    @MainActor func hasActiveSubscription() async -> Bool

    typealias TransactionJWS = String

    @MainActor func purchaseSubscription(with identifier: String, externalID: String) async -> Result<TransactionJWS, PurchaseManagerError>
}
