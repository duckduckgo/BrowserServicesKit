//
//  File.swift
//  
//
//  Created by Federico Cappelli on 06/05/2024.
//

import Foundation

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
