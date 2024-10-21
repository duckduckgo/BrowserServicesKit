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
    private let oAuthClient: OAuthClient
    private let subscriptionEndpointService: SubscriptionEndpointService
//    private let authEndpointService: AuthEndpointService
//    private let accountManager: AccountManager

    public init(subscriptionEndpointService: any SubscriptionEndpointService,
                oAuthClient: OAuthClient
//                authEndpointService: any AuthEndpointService,
//                accountManager: any AccountManager
    ) {
        self.subscriptionEndpointService = subscriptionEndpointService
//        self.authEndpointService = authEndpointService
//        self.accountManager = accountManager
        self.oAuthClient = oAuthClient
    }

    public func subscriptionOptions() async -> Result<SubscriptionOptions, StripePurchaseFlowError> {
        Logger.subscription.info("[StripePurchaseFlow] subscriptionOptions")

        guard let products = try? await subscriptionEndpointService.getProducts(), !products.isEmpty else {
            Logger.subscription.error("[StripePurchaseFlow] Error: noProductsFound")
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

    public func prepareSubscriptionPurchase(emailAccessToken: String?) async -> Result<PurchaseUpdate, StripePurchaseFlowError> {
        Logger.subscription.info("[StripePurchaseFlow] prepareSubscriptionPurchase")

        // Clear subscription Cache
        subscriptionEndpointService.signOut()

//        var token: String = ""
//        if let accessToken = try? await oAuthClient.getValidTokens().accessToken {
//            if await isSubscriptionExpired(accessToken: accessToken) {
//                token = accessToken
//            }
//        } else {
//            switch await authEndpointService.createAccount(emailAccessToken: emailAccessToken) {
//            case .success(let response):
//                token = response.authToken
//                accountManager.storeAuthToken(token: token)
//            case .failure:
//                Logger.subscription.error("[StripePurchaseFlow] Error: accountCreationFailed")
//                return .failure(.accountCreationFailed)
//            }
//        }

        do {
            let accessToken = try await oAuthClient.getTokens(policy: .createIfNeeded).accessToken
            if await isSubscriptionExpired(accessToken: accessToken) {
                return .success(PurchaseUpdate.redirect(withToken: accessToken))
            } else {
                return .success(PurchaseUpdate.redirect(withToken: ""))
            }

        } catch {
            Logger.subscription.error("[StripePurchaseFlow] Error: accountCreationFailed")
            return .failure(.accountCreationFailed)
        }
    }

    private func isSubscriptionExpired(accessToken: String) async -> Bool {
        if let subscription = try? await subscriptionEndpointService.getSubscription(accessToken: accessToken) {
            return !subscription.isActive
        }
        return false
    }

    public func completeSubscriptionPurchase() async {
        // Clear subscription Cache
        subscriptionEndpointService.signOut()

        // NONE OF THIS IS USEFUL ANYMORE, ACCESS TOKEN AND ACCOUNT DETAILS ARE OBTAINED AS PART OF THE AUTHENTICATION
//        Logger.subscription.info("[StripePurchaseFlow] completeSubscriptionPurchase")
//        if !accountManager.isUserAuthenticated,
//           let authToken = accountManager.authToken {
//            if case let .success(accessToken) = await accountManager.exchangeAuthTokenToAccessToken(authToken),
//               case let .success(accountDetails) = await accountManager.fetchAccountDetails(with: accessToken) {
//                accountManager.storeAuthToken(token: authToken)
//                accountManager.storeAccount(token: accessToken, email: accountDetails.email, externalID: accountDetails.externalID)
//            }
//        }
//        await accountManager.checkForEntitlements(wait: 2.0, retry: 5)
    }
}
