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
import Common

public final class StripePurchaseFlow {

    public enum Error: Swift.Error {
        case noProductsFound
        case accountCreationFailed
    }

    public static func subscriptionOptions() async -> Result<SubscriptionOptions, StripePurchaseFlow.Error> {
        os_log(.info, log: .subscription, "[StripePurchaseFlow] subscriptionOptions")

        guard case let .success(products) = await SubscriptionService.getProducts(), !products.isEmpty else {
            os_log(.error, log: .subscription, "[StripePurchaseFlow] Error: noProductsFound")
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

            return SubscriptionOption(id: $0.productId,
                                      cost: cost)
        }

        let features = SubscriptionFeatureName.allCases.map { SubscriptionFeature(name: $0.rawValue) }

        return .success(SubscriptionOptions(platform: SubscriptionPlatformName.stripe.rawValue,
                                            options: options,
                                            features: features))
    }

    public static func prepareSubscriptionPurchase(emailAccessToken: String?, subscriptionAppGroup: String) async -> Result<PurchaseUpdate, StripePurchaseFlow.Error> {
        os_log(.info, log: .subscription, "[StripePurchaseFlow] prepareSubscriptionPurchase")

        // Clear subscription Cache
        SubscriptionService.signOut()
        let accountManager = AccountManager(subscriptionAppGroup: subscriptionAppGroup)

        var token: String = ""

        if let accessToken = accountManager.accessToken {
            if await isSubscriptionExpired(accessToken: accessToken) {
                token = accessToken
            }
        } else {
            switch await AuthService.createAccount(emailAccessToken: emailAccessToken) {
            case .success(let response):
                token = response.authToken
                AccountManager(subscriptionAppGroup: subscriptionAppGroup).storeAuthToken(token: token)
            case .failure:
                os_log(.error, log: .subscription, "[StripePurchaseFlow] Error: accountCreationFailed")
                return .failure(.accountCreationFailed)
            }
        }

        return .success(PurchaseUpdate(type: "redirect", token: token))
    }

    private static func isSubscriptionExpired(accessToken: String) async -> Bool {
        if case .success(let subscription) = await SubscriptionService.getSubscription(accessToken: accessToken) {
            return !subscription.isActive
        }

        return false
    }

    public static func completeSubscriptionPurchase(subscriptionAppGroup: String) async {

        // Clear subscription Cache
        SubscriptionService.signOut()

        os_log(.info, log: .subscription, "[StripePurchaseFlow] completeSubscriptionPurchase")

        let accountManager = AccountManager(subscriptionAppGroup: subscriptionAppGroup)

        if !accountManager.isUserAuthenticated,
           let authToken = accountManager.authToken {
            if case let .success(accessToken) = await accountManager.exchangeAuthTokenToAccessToken(authToken),
               case let .success(accountDetails) = await accountManager.fetchAccountDetails(with: accessToken) {
                accountManager.storeAuthToken(token: authToken)
                accountManager.storeAccount(token: accessToken, email: accountDetails.email, externalID: accountDetails.externalID)
            }
        }

        await AccountManager.checkForEntitlements(subscriptionAppGroup: subscriptionAppGroup, wait: 2.0, retry: 5)
    }
}
