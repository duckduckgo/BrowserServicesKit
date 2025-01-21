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

public enum AppStorePurchaseFlowError: Swift.Error, Equatable, LocalizedError {
    case noProductsFound
    case activeSubscriptionAlreadyPresent
    case authenticatingWithTransactionFailed
    case accountCreationFailed(Swift.Error)
    case purchaseFailed(Swift.Error)
    case cancelledByUser
    case missingEntitlements
    case internalError(Swift.Error?)

    public var errorDescription: String? {
        switch self {
        case .noProductsFound:
            "No products found"
        case .activeSubscriptionAlreadyPresent:
            "An active subscription is already present"
        case .authenticatingWithTransactionFailed:
            "Authenticating with transaction failed"
        case .accountCreationFailed(let subError):
            "Account creation failed: \(subError.localizedDescription)"
        case .purchaseFailed(let subError):
            "Purchase failed: \(subError.localizedDescription)"
        case .cancelledByUser:
            "Purchase cancelled by user"
        case .missingEntitlements:
            "Missing entitlements"
        case .internalError(let error):
            "Internal error: \(error?.localizedDescription ?? "<nil>" )"
        }
    }

    public static func == (lhs: AppStorePurchaseFlowError, rhs: AppStorePurchaseFlowError) -> Bool {
        switch (lhs, rhs) {
        case (.noProductsFound, .noProductsFound),
            (.activeSubscriptionAlreadyPresent, .activeSubscriptionAlreadyPresent),
            (.authenticatingWithTransactionFailed, .authenticatingWithTransactionFailed),
            (.cancelledByUser, .cancelledByUser),
            (.missingEntitlements, .missingEntitlements),
            (.internalError, .internalError):
            return true
        case let (.accountCreationFailed(lhsError), .accountCreationFailed(rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case let (.purchaseFailed(lhsError), .purchaseFailed(rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
public protocol AppStorePurchaseFlow {
    typealias TransactionJWS = String
    func purchaseSubscription(with subscriptionIdentifier: String) async -> Result<TransactionJWS, AppStorePurchaseFlowError>

    /// Completes the subscription purchase by validating the transaction.
    ///
    /// - Parameters:
    ///   - transactionJWS: The JWS representation of the transaction to be validated.
    ///   - additionalParams: Optional additional parameters to send with the transaction validation request.
    /// - Returns: A `Result` containing either a `PurchaseUpdate` object on success or an `AppStorePurchaseFlowError` on failure.
    @discardableResult func completeSubscriptionPurchase(with transactionJWS: TransactionJWS, additionalParams: [String: String]?) async -> Result<PurchaseUpdate, AppStorePurchaseFlowError>
}

@available(macOS 12.0, iOS 15.0, *)
public final class DefaultAppStorePurchaseFlow: AppStorePurchaseFlow {
    private let subscriptionManager: any SubscriptionManager
    private let storePurchaseManager: StorePurchaseManager
    private let appStoreRestoreFlow: AppStoreRestoreFlow

    public init(subscriptionManager: any SubscriptionManager,
                storePurchaseManager: any StorePurchaseManager,
                appStoreRestoreFlow: any AppStoreRestoreFlow
    ) {
        self.subscriptionManager = subscriptionManager
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

            // Try to restore an account from a past purchase
            switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
            case .success:
                Logger.subscriptionAppStorePurchaseFlow.log("An active subscription is already present")
                return .failure(.activeSubscriptionAlreadyPresent)
            case .failure(let error):
                Logger.subscriptionAppStorePurchaseFlow.log("Failed to restore an account from a past purchase: \(error.localizedDescription, privacy: .public)")
                do {
                    externalID = try await subscriptionManager.getTokenContainer(policy: .createIfNeeded).decodedAccessToken.externalID
                } catch OAuthClientError.deadToken {
                    do {
                        let transactionJWS = try await recoverSubscriptionFromDeadToken()
                        return .success(transactionJWS)
                    } catch {
                        return .failure(.purchaseFailed(OAuthClientError.deadToken))
                    }
                } catch Networking.OAuthClientError.missingTokens {
                    Logger.subscriptionStripePurchaseFlow.error("Failed to create a new account: \(error.localizedDescription, privacy: .public)")
                    return .failure(.accountCreationFailed(error))
                } catch {
                    Logger.subscriptionStripePurchaseFlow.fault("Failed to create a new account: \(error.localizedDescription, privacy: .public), the operation is unrecoverable")
                    return .failure(.internalError(error))
                }
            }
        }

        guard let externalID else {
            Logger.subscriptionAppStorePurchaseFlow.fault("Missing external ID, subscription purchase failed")
            return .failure(.internalError(nil))
        }

        // Make the purchase
        switch await storePurchaseManager.purchaseSubscription(with: subscriptionIdentifier, externalID: externalID) {
        case .success(let transactionJWS):
            return .success(transactionJWS)
        case .failure(let error):
            Logger.subscriptionAppStorePurchaseFlow.error("purchaseSubscription error: \(String(reflecting: error), privacy: .public)")

            await subscriptionManager.signOut(notifyUI: true)

            switch error {
            case .purchaseCancelledByUser:
                return .failure(.cancelledByUser)
            default:
                return .failure(.purchaseFailed(error))
            }
        }
    }

    @discardableResult
    public func completeSubscriptionPurchase(with transactionJWS: TransactionJWS, additionalParams: [String: String]?) async -> Result<PurchaseUpdate, AppStorePurchaseFlowError> {
        Logger.subscriptionAppStorePurchaseFlow.log("Completing Subscription Purchase")
        subscriptionManager.clearSubscriptionCache()

        do {
            let subscription = try await subscriptionManager.confirmPurchase(signature: transactionJWS, additionalParams: additionalParams)
            let refreshedToken = try await subscriptionManager.getTokenContainer(policy: .localForceRefresh)
            if subscription.isActive {
                if refreshedToken.decodedAccessToken.subscriptionEntitlements.isEmpty {
                    Logger.subscriptionAppStorePurchaseFlow.error("Missing entitlements")
                    return .failure(.missingEntitlements)
                } else {
                    return .success(.completed)
                }
            } else {
                Logger.subscriptionAppStorePurchaseFlow.error("Subscription expired")
                return .failure(.purchaseFailed(AppStoreRestoreFlowError.subscriptionExpired))
            }
        } catch OAuthClientError.deadToken {
            do {
                try await recoverSubscriptionFromDeadToken()
                return .success(.completed)
            } catch {
                return .failure(.purchaseFailed(OAuthClientError.deadToken))
            }
        } catch {
            Logger.subscriptionAppStorePurchaseFlow.error("Purchase Failed: \(error)")
            return .failure(.purchaseFailed(error))
        }
    }

    private func getExpiredSubscriptionID() async -> String? {
        do {
            let subscription = try await subscriptionManager.getSubscription(cachePolicy: .reloadIgnoringLocalCacheData)
            // Only return an externalID if the subscription is expired so to prevent creating multiple subscriptions in the same account
            if !subscription.isActive,
               subscription.platform != .apple {
                return try await subscriptionManager.getTokenContainer(policy: .localValid).decodedAccessToken.externalID
            }
            return nil
        } catch OAuthClientError.deadToken {
            do {
                try await recoverSubscriptionFromDeadToken()
                return try? await subscriptionManager.getTokenContainer(policy: .localValid).decodedAccessToken.externalID
            } catch {
                Logger.subscription.error("Failed to retrieve the current subscription: Missing transaction JWS")
                return nil
            }
        } catch {
            return nil
        }
    }

    @discardableResult
    private func recoverSubscriptionFromDeadToken() async throws -> String {
        Logger.subscriptionAppStorePurchaseFlow.log("Recovering Subscription From Dead Token")

        // Clear everything, the token is unrecoverable
        await subscriptionManager.signOut(notifyUI: true)

        switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
        case .success(let transactionJWS):
            Logger.subscriptionAppStorePurchaseFlow.log("Subscription recovered")
            return transactionJWS
        case .failure(let error):
            Logger.subscriptionAppStorePurchaseFlow.log("Failed to recover Apple subscription: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
