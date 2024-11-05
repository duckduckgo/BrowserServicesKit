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
    private let subscriptionManager: SubscriptionManager
    private let subscriptionEndpointService: SubscriptionEndpointService

    public init(subscriptionManager: SubscriptionManager,
                subscriptionEndpointService: any SubscriptionEndpointService) {
        self.subscriptionManager = subscriptionManager
        self.subscriptionEndpointService = subscriptionEndpointService
    }

    public func subscriptionOptions() async -> Result<SubscriptionOptions, StripePurchaseFlowError> {
        Logger.subscriptionStripePurchaseFlow.log("Getting subscription options")

        guard let products = try? await subscriptionEndpointService.getProducts(), !products.isEmpty else {
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

        let features = SubscriptionFeatureName.allCases.map { SubscriptionFeature(name: $0.rawValue) }
        return .success(SubscriptionOptions(platform: SubscriptionPlatformName.stripe.rawValue, options: options, features: features))
    }

    public func prepareSubscriptionPurchase(emailAccessToken: String?) async -> Result<PurchaseUpdate, StripePurchaseFlowError> {

        Logger.subscription.log("Preparing subscription purchase")
        subscriptionEndpointService.clearSubscription()
        do {
            let accessToken = try await subscriptionManager.getTokenContainer(policy: .createIfNeeded).accessToken
            if let subscription = try? await subscriptionEndpointService.getSubscription(accessToken: accessToken),
               !subscription.isActive {
                return .success(PurchaseUpdate.redirect(withToken: accessToken))
            } else {
                return .success(PurchaseUpdate.redirect(withToken: ""))
            }
        } catch {
            Logger.subscriptionStripePurchaseFlow.error("Account creation failed: \(error.localizedDescription, privacy: .public)")
            return .failure(.accountCreationFailed)
        }
    }

    public func completeSubscriptionPurchase() async {
        Logger.subscriptionStripePurchaseFlow.log("Completing subscription purchase")
        subscriptionEndpointService.clearSubscription()
        _ = try? await subscriptionManager.getTokenContainer(policy: .localForceRefresh)
    }
}
