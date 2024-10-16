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
//    private let accountManager: AccountManager
    private let appStoreRestoreFlow: AppStoreRestoreFlow
//    private let authEndpointService: AuthEndpointService

    public init(oAuthClient: OAuthClient,
                subscriptionEndpointService: any SubscriptionEndpointService,
                storePurchaseManager: any StorePurchaseManager,
//                accountManager: any AccountManager,
                appStoreRestoreFlow: any AppStoreRestoreFlow
//                authEndpointService: any AuthEndpointService
    ) {
        self.oAuthClient = oAuthClient
        self.subscriptionEndpointService = subscriptionEndpointService
        self.storePurchaseManager = storePurchaseManager
//        self.accountManager = accountManager
        self.appStoreRestoreFlow = appStoreRestoreFlow
//        self.authEndpointService = authEndpointService
    }

//    public func purchaseSubscription(with subscriptionIdentifier: String) async -> Result<TransactionJWS, AppStorePurchaseFlowError> {
//        Logger.subscriptionAppStorePurchaseFlow.debug("purchaseSubscription")
//        let externalID: String
//
//        // If the current account is a third party expired account, we want to purchase and attach subs to it
//        if let existingExternalID = await getExpiredSubscriptionID() {
//            externalID = existingExternalID
//        } else { // Otherwise, try to retrieve an expired Apple subscription or create a new one
//
//            // Check for past transactions most recent
//            switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
//            case .success:
//                Logger.subscriptionAppStorePurchaseFlow.error("purchaseSubscription -> restoreAccountFromPastPurchase: activeSubscriptionAlreadyPresent")
//                return .failure(.activeSubscriptionAlreadyPresent)
//            case .failure(let error):
//                Logger.subscriptionAppStorePurchaseFlow.debug("purchaseSubscription -> restoreAccountFromPastPurchase: \(error.localizedDescription, privacy: .public)")
//
//                switch error {
//                case .subscriptionExpired(let expiredAccountTokens):
////                    accountManager.storeAuthToken(token: expiredAccountTokens.authToken)
////                    accountManager.storeAccount(token: expiredAccountTokens.accessToken,
////                                                email: expiredAccountTokens.decodedAccessToken.email,
////                                                externalID: expiredAccountTokens.decodedAccessToken.externalID)
//
//
//                default:
//                    switch await authEndpointService.createAccount(emailAccessToken: emailAccessToken) {
//                    case .success(let response):
//                        externalID = response.externalID
//
//                        if case let .success(accessToken) = await accountManager.exchangeAuthTokenToAccessToken(response.authToken),
//                           case let .success(accountDetails) = await accountManager.fetchAccountDetails(with: accessToken) {
//                            accountManager.storeAuthToken(token: response.authToken)
//                            accountManager.storeAccount(token: accessToken, email: accountDetails.email, externalID: accountDetails.externalID)
//                        }
//                    case .failure(let error):
//                        Logger.subscriptionAppStorePurchaseFlow.error("createAccount error: \(String(reflecting: error), privacy: .public)")
//                        return .failure(.accountCreationFailed)
//                    }
//                }
//            }
//        }
//
//        // Make the purchase
//        switch await storePurchaseManager.purchaseSubscription(with: subscriptionIdentifier, externalID: externalID) {
//        case .success(let transactionJWS):
//            return .success(transactionJWS)
//        case .failure(let error):
//            Logger.subscriptionAppStorePurchaseFlow.error("purchaseSubscription error: \(String(reflecting: error), privacy: .public)")
//            accountManager.signOut(skipNotification: true)
//            switch error {
//            case .purchaseCancelledByUser:
//                return .failure(.cancelledByUser)
//            default:
//                return .failure(.purchaseFailed)
//            }
//        }
//    }

    public func purchaseSubscription(with subscriptionIdentifier: String) async -> Result<TransactionJWS, AppStorePurchaseFlowError> {
        Logger.subscriptionAppStorePurchaseFlow.debug("Purchase Subscription")

        var externalID: String? = nil
        // If the current account is a third party expired account, we want to purchase and attach subs to it
        if let existingExternalID = await getExpiredSubscriptionID() {
            externalID = existingExternalID
        } else { // Otherwise, try to retrieve an expired Apple subscription or create a new one

            // Check for past transactions most recent
            switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
            case .success():
                Logger.subscriptionAppStorePurchaseFlow.error("purchaseSubscription -> restoreAccountFromPastPurchase: activeSubscriptionAlreadyPresent")
                return .failure(.activeSubscriptionAlreadyPresent)
            case .failure(let error):
                Logger.subscriptionAppStorePurchaseFlow.debug("purchaseSubscription -> restoreAccountFromPastPurchase: \(error.localizedDescription, privacy: .public)")
                externalID = try? await oAuthClient.getTokens(policy: .valid).decodedAccessToken.externalID
                break
            }
        }

        guard let externalID else {
            Logger.subscriptionAppStorePurchaseFlow.error("purchaseSubscription -> externalID is nil")
            return .failure(.internalError)
        }

        // Make the purchase
        switch await storePurchaseManager.purchaseSubscription(with: subscriptionIdentifier, externalID: externalID) {
        case .success(let transactionJWS):
            return .success(transactionJWS)
        case .failure(let error):
            Logger.subscriptionAppStorePurchaseFlow.error("purchaseSubscription error: \(String(reflecting: error), privacy: .public)")
            //                accountManager.signOut(skipNotification: true)
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
            let accessToken = try await oAuthClient.getTokens(policy: .valid).accessToken
            do {
                let confirmation = try await subscriptionEndpointService.confirmPurchase(accessToken: accessToken, signature: transactionJWS)
                subscriptionEndpointService.updateCache(with: confirmation.subscription)
                try await oAuthClient.refreshTokens()
                return .success(PurchaseUpdate.completed)
            } catch {
                return .failure(.purchaseFailed(error))
            }
        } catch {
            return .failure(AppStorePurchaseFlowError.accountCreationFailed(error))
        }
    }

    private func getExpiredSubscriptionID() async -> String? {
        do {
            let tokenStorage = try await oAuthClient.getTokens(policy: .valid)
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
