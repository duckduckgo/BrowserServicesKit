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
    private let oAuthClient: OAuthClient
    private let subscriptionEndpointService: SubscriptionEndpointService
    private let storePurchaseManager: StorePurchaseManager
    private let appStoreRestoreFlow: AppStoreRestoreFlow

    public init(oAuthClient: OAuthClient,
                subscriptionEndpointService: any SubscriptionEndpointService,
                storePurchaseManager: any StorePurchaseManager,
                appStoreRestoreFlow: any AppStoreRestoreFlow
    ) {
        self.oAuthClient = oAuthClient
        self.subscriptionEndpointService = subscriptionEndpointService
        self.storePurchaseManager = storePurchaseManager
        self.appStoreRestoreFlow = appStoreRestoreFlow
    }

    public func purchaseSubscription(with subscriptionIdentifier: String) async -> Result<TransactionJWS, AppStorePurchaseFlowError> {
        Logger.subscriptionAppStorePurchaseFlow.debug("Purchasing Subscription")

        var externalID: String?
        // If the current account is a third party expired account, we want to purchase and attach subs to it
        if let existingExternalID = await getExpiredSubscriptionID() {
            Logger.subscriptionAppStorePurchaseFlow.debug("External ID retrieved from expired subscription")
            externalID = existingExternalID
        } else {
            Logger.subscriptionAppStorePurchaseFlow.debug("Try to retrieve an expired Apple subscription or create a new one")
            // Check for past transactions most recent
            switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
            case .success:
                Logger.subscriptionAppStorePurchaseFlow.debug("An active subscription is already present")
                return .failure(.activeSubscriptionAlreadyPresent)
            case .failure(let error):
                Logger.subscriptionAppStorePurchaseFlow.debug("Failed to restore an account from a past purchase: \(error.localizedDescription, privacy: .public)")
                do {
                    let newAccountExternalID = try await oAuthClient.getTokens(policy: .createIfNeeded).decodedAccessToken.externalID
                    externalID = newAccountExternalID
                } catch {
                    Logger.subscriptionStripePurchaseFlow.error("Failed to create a new account: \(error.localizedDescription, privacy: .public), the operation is unrecoverable")
                    return .failure(.internalError)
                }
            }
        }

        guard let externalID else {
            Logger.subscriptionAppStorePurchaseFlow.fault("Missing externalID, subscription purchase failed")
            return .failure(.internalError)
        }

        // Make the purchase
        switch await storePurchaseManager.purchaseSubscription(with: subscriptionIdentifier, externalID: externalID) {
        case .success(let transactionJWS):
            return .success(transactionJWS)
        case .failure(let error):
            Logger.subscriptionAppStorePurchaseFlow.error("purchaseSubscription error: \(String(reflecting: error), privacy: .public)")
            oAuthClient.removeLocalAccount()
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
        Logger.subscriptionAppStorePurchaseFlow.debug("Complete Subscription Purchase")

        // Clear subscription Cache
        subscriptionEndpointService.signOut()

        do {
            let accessToken = try await oAuthClient.getTokens(policy: .localValid).accessToken
            do {
                let confirmation = try await subscriptionEndpointService.confirmPurchase(accessToken: accessToken, signature: transactionJWS)
                subscriptionEndpointService.updateCache(with: confirmation.subscription)
                try await oAuthClient.refreshTokens()
                return .success(PurchaseUpdate.completed)
            } catch {
                Logger.subscriptionAppStorePurchaseFlow.error("Purchase Failed: \(error)")
                return .failure(.purchaseFailed(error))
            }
        } catch {
            Logger.subscriptionAppStorePurchaseFlow.error("Purchase Failed: \(error)")
            return .failure(AppStorePurchaseFlowError.accountCreationFailed(error))
        }
    }

    private func getExpiredSubscriptionID() async -> String? {
        do {
            let tokenStorage = try await oAuthClient.getTokens(policy: .localValid)
            let subscription = try await subscriptionEndpointService.getSubscription(accessToken: tokenStorage.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)

            // Only return an externalID if the subscription is expired so to prevent creating multiple subscriptions in the same account
            if subscription.isActive == false,
               subscription.platform != .apple {
                return tokenStorage.decodedAccessToken.externalID
            }
            return nil
        } catch {
            return nil
        }
    }
}
