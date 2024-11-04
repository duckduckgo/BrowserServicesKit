//
//  AppStorePurchaseFlow.swift
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

import Foundation
import StoreKit
import os.log
import Networking

public enum AppStorePurchaseFlowError: Swift.Error {
    case noProductsFound
    case activeSubscriptionAlreadyPresent
    case authenticatingWithTransactionFailed
    case accountCreationFailed(Swift.Error)
    case purchaseFailed(Swift.Error)
    case cancelledByUser
    case missingEntitlements
    case internalError
}

@available(macOS 12.0, iOS 15.0, *)
public protocol AppStorePurchaseFlow {
    typealias TransactionJWS = String
    func purchaseSubscription(with subscriptionIdentifier: String) async -> Result<TransactionJWS, AppStorePurchaseFlowError>
    @discardableResult func completeSubscriptionPurchase(with transactionJWS: TransactionJWS) async -> Result<PurchaseUpdate, AppStorePurchaseFlowError>
}

@available(macOS 12.0, iOS 15.0, *)
public final class DefaultAppStorePurchaseFlow: AppStorePurchaseFlow {
    private let subscriptionManager: any SubscriptionManager
//    private let subscriptionEndpointService: SubscriptionEndpointService
    private let storePurchaseManager: StorePurchaseManager
    private let appStoreRestoreFlow: AppStoreRestoreFlow

    public init(subscriptionManager: any SubscriptionManager,
//                subscriptionEndpointService: any SubscriptionEndpointService,
                storePurchaseManager: any StorePurchaseManager,
                appStoreRestoreFlow: any AppStoreRestoreFlow
    ) {
        self.subscriptionManager = subscriptionManager
//        self.subscriptionEndpointService = subscriptionEndpointService
        self.storePurchaseManager = storePurchaseManager
        self.appStoreRestoreFlow = appStoreRestoreFlow
    }

    public func purchaseSubscription(with subscriptionIdentifier: String) async -> Result<TransactionJWS, AppStorePurchaseFlowError> {
        Logger.subscriptionAppStorePurchaseFlow.log("Purchasing Subscription")

        var externalID: String?
        if let existingExternalID = await getExpiredSubscriptionID() {
            Logger.subscriptionAppStorePurchaseFlow.log("External ID retrieved from expired subscription")
            externalID = existingExternalID
        } else {
            Logger.subscriptionAppStorePurchaseFlow.log("Try to retrieve an expired Apple subscription or create a new one")
            // Check for past transactions most recent
            switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
            case .success:
                Logger.subscriptionAppStorePurchaseFlow.log("An active subscription is already present")
                return .failure(.activeSubscriptionAlreadyPresent)
            case .failure(let error):
                Logger.subscriptionAppStorePurchaseFlow.log("Failed to restore an account from a past purchase: \(error.localizedDescription, privacy: .public)")
                do {
                    let newAccountExternalID = try await subscriptionManager.getTokenContainer(policy: .createIfNeeded).decodedAccessToken.externalID
                    externalID = newAccountExternalID
                } catch {
                    Logger.subscriptionStripePurchaseFlow.error("Failed to create a new account: \(error.localizedDescription, privacy: .public), the operation is unrecoverable")
                    return .failure(.internalError)
                }
            }
        }

        guard let externalID else {
            Logger.subscriptionAppStorePurchaseFlow.fault("Missing external ID, subscription purchase failed")
            return .failure(.internalError)
        }

        // Make the purchase
        switch await storePurchaseManager.purchaseSubscription(with: subscriptionIdentifier, externalID: externalID) {
        case .success(let transactionJWS):
            return .success(transactionJWS)
        case .failure(let error):
            Logger.subscriptionAppStorePurchaseFlow.error("purchaseSubscription error: \(String(reflecting: error), privacy: .public)")

            await subscriptionManager.signOut()

            switch error {
            case .purchaseCancelledByUser:
                return .failure(.cancelledByUser)
            default:
                return .failure(.purchaseFailed(error))
            }
        }
    }

    @discardableResult
    public func completeSubscriptionPurchase(with transactionJWS: TransactionJWS) async -> Result<PurchaseUpdate, AppStorePurchaseFlowError> {
        Logger.subscriptionAppStorePurchaseFlow.log("Completing Subscription Purchase")

        // Clear subscription Cache
//        await subscriptionManager.signOut()
        subscriptionManager.clearSubscriptionCache()

        do {
            let subscription = try await subscriptionManager.confirmPurchase(signature: transactionJWS)
            if subscription.isActive {

                //                return await refreshTokensUntilEntitlementsAvailable() ? .success(PurchaseUpdate.completed) : .failure(.missingEntitlements)

                let refreshedToken = try await subscriptionManager.getTokenContainer(policy: .localForceRefresh)
                if refreshedToken.decodedAccessToken.entitlements.isEmpty {
                    Logger.subscriptionAppStorePurchaseFlow.error("Missing entitlements")
                    return .failure(.missingEntitlements)
                } else {
                    return .success(PurchaseUpdate.completed)
                }
            } else {
                Logger.subscriptionAppStorePurchaseFlow.error("Subscription expired")
                // Removing all traces of the subscription and the account
                return .failure(.purchaseFailed(AppStoreRestoreFlowError.subscriptionExpired))
            }
        } catch {
            Logger.subscriptionAppStorePurchaseFlow.error("Purchase Failed: \(error)")
            return .failure(.purchaseFailed(error))
        }
    }

    func refreshTokensUntilEntitlementsAvailable() async -> Bool {
        // Refresh token until entitlements are available
        return await callWithRetries(retry: 5, wait: 2.0) {
            guard let refreshedToken = try? await subscriptionManager.getTokenContainer(policy: .localForceRefresh) else {
                return false
            }
            if refreshedToken.decodedAccessToken.entitlements.isEmpty {
                Logger.subscriptionAppStorePurchaseFlow.error("Missing entitlements")
                return false
            } else {
                return true
            }
        }
    }

    private func callWithRetries(retry retryCount: Int, wait waitTime: Double, conditionToCheck: () async -> Bool) async -> Bool {
        var count = 0
        var successful = false

        repeat {
            successful = await conditionToCheck()

            if successful {
                break
            } else {
                count += 1
                try? await Task.sleep(interval: waitTime)
            }
        } while !successful && count < retryCount

        return successful
    }

    private func getExpiredSubscriptionID() async -> String? {
        do {
            let subscription = try await subscriptionManager.currentSubscription(refresh: true)
            // Only return an externalID if the subscription is expired so to prevent creating multiple subscriptions in the same account
            if !subscription.isActive,
               subscription.platform != .apple {
                return try? await subscriptionManager.getTokenContainer(policy: .localValid).decodedAccessToken.externalID
            }
            return nil
        } catch {
            return nil
        }
    }
}
