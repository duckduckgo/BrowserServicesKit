//
//  StripePurchaseFlow.swift
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

public enum StripePurchaseFlowError: Swift.Error {
    case noProductsFound
    case accountCreationFailed
}

public protocol StripePurchaseFlow {
    func subscriptionOptions() async -> Result<SubscriptionOptions, StripePurchaseFlowError>
    func prepareSubscriptionPurchase(emailAccessToken: String?) async -> Result<PurchaseUpdate, StripePurchaseFlowError>
    func completeSubscriptionPurchase() async
}

public final class DefaultStripePurchaseFlow: StripePurchaseFlow {
    private let subscriptionManager: any SubscriptionManager

    public init(subscriptionManager: any SubscriptionManager) {
        self.subscriptionManager = subscriptionManager
    }

    public func subscriptionOptions() async -> Result<SubscriptionOptions, StripePurchaseFlowError> {
        Logger.subscriptionStripePurchaseFlow.log("Getting subscription options for Stripe")

        guard let products = try? await subscriptionManager.getProducts(),
              !products.isEmpty else {
            Logger.subscriptionStripePurchaseFlow.error("Failed to obtain products")
            return .failure(.noProductsFound)
        }

        let currency = products.first?.currency ?? "USD"

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US@currency=\(currency)")

        let options: [SubscriptionOption] = products.map {
            var displayPrice = "\($0.price) \($0.currency)"

            if let price = Float($0.price), let formattedPrice = formatter.string(from: price as NSNumber) {
                 displayPrice = formattedPrice
            }
            let cost = SubscriptionOptionCost(displayPrice: displayPrice, recurrence: $0.billingPeriod.lowercased())
            return SubscriptionOption(id: $0.productId, cost: cost)
        }

        let features: [SubscriptionEntitlement] = [.networkProtection,
                                                  .dataBrokerProtection,
                                                  .identityTheftRestoration]
        return .success(SubscriptionOptions(platform: SubscriptionPlatformName.stripe,
                                            options: options,
                                            availableEntitlements: features))
    }

    public func prepareSubscriptionPurchase(emailAccessToken: String?) async -> Result<PurchaseUpdate, StripePurchaseFlowError> {
        Logger.subscription.log("Preparing subscription purchase")

        subscriptionManager.clearSubscriptionCache()

        if subscriptionManager.isUserAuthenticated {
            if let subscriptionExpired = await isSubscriptionExpired(),
               subscriptionExpired == true,
               let tokenContainer = try? await subscriptionManager.getTokenContainer(policy: .localValid) {
                return .success(PurchaseUpdate.redirect(withToken: tokenContainer.accessToken))
            } else {
                return .success(PurchaseUpdate.redirect(withToken: ""))
            }
        } else {
            do {
                // Create account
                let tokenContainer = try await subscriptionManager.getTokenContainer(policy: .createIfNeeded)
                return .success(PurchaseUpdate.redirect(withToken: tokenContainer.accessToken))
            } catch {
                Logger.subscriptionStripePurchaseFlow.error("Account creation failed: \(error.localizedDescription, privacy: .public)")
                return .failure(.accountCreationFailed)
            }
        }
    }

    private func isSubscriptionExpired() async -> Bool? {
        guard let subscription = try? await subscriptionManager.getSubscription(cachePolicy: .reloadIgnoringLocalCacheData) else {
            return nil
        }
        return !subscription.isActive
    }

    public func completeSubscriptionPurchase() async {
        Logger.subscriptionStripePurchaseFlow.log("Completing subscription purchase")
        subscriptionManager.clearSubscriptionCache()
        _ = try? await subscriptionManager.getTokenContainer(policy: .localForceRefresh)
    }
}
