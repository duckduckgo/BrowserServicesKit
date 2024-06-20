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
import Common

public typealias TransactionJWS = String

public enum AppStorePurchaseFlowError: Swift.Error {
    case noProductsFound
    case activeSubscriptionAlreadyPresent
    case authenticatingWithTransactionFailed
    case accountCreationFailed
    case purchaseFailed
    case cancelledByUser
    case missingEntitlements
    case internalError
}

@available(macOS 12.0, iOS 15.0, *)
public protocol AppStorePurchaseFlow {
    func purchaseSubscription(with subscriptionIdentifier: String, emailAccessToken: String?) async -> Result<TransactionJWS, AppStorePurchaseFlowError>
    @discardableResult
    func completeSubscriptionPurchase(with transactionJWS: TransactionJWS) async -> Result<PurchaseUpdate, AppStorePurchaseFlowError>
}

@available(macOS 12.0, iOS 15.0, *)
public final class DefaultAppStorePurchaseFlow: AppStorePurchaseFlow {

    private let subscriptionManager: SubscriptionManager
    private var accountManager: AccountManager { subscriptionManager.accountManager }
    private let appStoreRestoreFlow: AppStoreRestoreFlow

    public init(subscriptionManager: SubscriptionManager, appStoreRestoreFlow: AppStoreRestoreFlow) {
        self.subscriptionManager = subscriptionManager
        self.appStoreRestoreFlow = appStoreRestoreFlow
    }

    // swiftlint:disable cyclomatic_complexity
    public func purchaseSubscription(with subscriptionIdentifier: String, emailAccessToken: String?) async -> Result<TransactionJWS, AppStorePurchaseFlowError> {
        os_log(.info, log: .subscription, "[AppStorePurchaseFlow] purchaseSubscription")
        let externalID: String

        // If the current account is a third party expired account, we want to purchase and attach subs to it
        if let existingExternalID = await getExpiredSubscriptionID() {
            externalID = existingExternalID

        // Otherwise, try to retrieve an expired Apple subscription or create a new one
        } else {
            // Check for past transactions most recent
            switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
            case .success:
                os_log(.info, log: .subscription, "[AppStorePurchaseFlow] purchaseSubscription -> restoreAccountFromPastPurchase: activeSubscriptionAlreadyPresent")
                return .failure(.activeSubscriptionAlreadyPresent)
            case .failure(let error):
                os_log(.info, log: .subscription, "[AppStorePurchaseFlow] purchaseSubscription -> restoreAccountFromPastPurchase: %{public}s", String(reflecting: error))
                switch error {
                case .subscriptionExpired(let expiredAccountDetails):
                    externalID = expiredAccountDetails.externalID
                    accountManager.storeAuthToken(token: expiredAccountDetails.authToken)
                    accountManager.storeAccount(token: expiredAccountDetails.accessToken, email: expiredAccountDetails.email, externalID: expiredAccountDetails.externalID)
                default:
                    switch await subscriptionManager.authEndpointService.createAccount(emailAccessToken: emailAccessToken) {
                    case .success(let response):
                        externalID = response.externalID

                        if case let .success(accessToken) = await accountManager.exchangeAuthTokenToAccessToken(response.authToken),
                           case let .success(accountDetails) = await accountManager.fetchAccountDetails(with: accessToken) {
                            accountManager.storeAuthToken(token: response.authToken)
                            accountManager.storeAccount(token: accessToken, email: accountDetails.email, externalID: accountDetails.externalID)
                        }
                    case .failure(let error):
                        os_log(.error, log: .subscription, "[AppStorePurchaseFlow] createAccount error: %{public}s", String(reflecting: error))
                        return .failure(.accountCreationFailed)
                    }
                }
            }
        }

        // Make the purchase
        switch await subscriptionManager.storePurchaseManager().purchaseSubscription(with: subscriptionIdentifier, externalID: externalID) {
        case .success(let transactionJWS):
            return .success(transactionJWS)
        case .failure(let error):
            os_log(.error, log: .subscription, "[AppStorePurchaseFlow] purchaseSubscription error: %{public}s", String(reflecting: error))
            accountManager.signOut(skipNotification: true)
            switch error {
            case .purchaseCancelledByUser:
                return .failure(.cancelledByUser)
            default:
                return .failure(.purchaseFailed)
            }
        }
    }

    // swiftlint:enable cyclomatic_complexity
    @discardableResult
    public func completeSubscriptionPurchase(with transactionJWS: TransactionJWS) async -> Result<PurchaseUpdate, AppStorePurchaseFlowError> {

        // Clear subscription Cache
        subscriptionManager.subscriptionEndpointService.signOut()

        os_log(.info, log: .subscription, "[AppStorePurchaseFlow] completeSubscriptionPurchase")

        guard let accessToken = accountManager.accessToken else { return .failure(.missingEntitlements) }

        let result = await callWithRetries(retry: 5, wait: 2.0) {
            switch await subscriptionManager.subscriptionEndpointService.confirmPurchase(accessToken: accessToken, signature: transactionJWS) {
            case .success(let confirmation):
                subscriptionManager.subscriptionEndpointService.updateCache(with: confirmation.subscription)
                accountManager.updateCache(with: confirmation.entitlements)
                return true
            case .failure:
                return false
            }
        }

        return result ? .success(PurchaseUpdate(type: "completed")) : .failure(.missingEntitlements)
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
                try? await Task.sleep(seconds: waitTime)
            }
        } while !successful && count < retryCount

        return successful
    }

    private func getExpiredSubscriptionID() async -> String? {
        guard accountManager.isUserAuthenticated,
              let externalID = accountManager.externalID,
              let token = accountManager.accessToken
        else { return nil }

        let subscriptionInfo = await subscriptionManager.subscriptionEndpointService.getSubscription(accessToken: token, cachePolicy: .reloadIgnoringLocalCacheData)

        // Only return an externalID if the subscription is expired
        // To prevent creating multiple subscriptions in the same account
        if case .success(let subscription) = subscriptionInfo,
           !subscription.isActive,
            subscription.platform != .apple {
            return externalID
        }
        return nil
    }
}
