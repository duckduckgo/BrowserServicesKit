//
//  SubscriptionMockFactory.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import Subscription

/// Provides all mocks needed for testing subscription initialised with positive outcomes and basic configurations. All mocks can be partially reconfigured with failures or incorrect data
public struct SubscriptionMockFactory {

    public static let email = "5p2d4sx1@duck.com" // Some sandbox account
    public static let externalId = UUID().uuidString
    public static let accountManager = AccountManagerMock(email: email,
                                                          externalID: externalId)
    /// No mock result or error configured, that must be done per-test basis
    public static let apiService = APIServiceMock(mockAuthHeaders: [:])
    public static let subscription = Subscription(productId: UUID().uuidString,
                                                  name: "Subscription test #1",
                                                  billingPeriod: .monthly,
                                                  startedAt: Date(),
                                                  expiresOrRenewsAt: Date().addingTimeInterval(TimeInterval.days(+30)),
                                                  platform: .apple,
                                                  status: .autoRenewable)
    public static let productsItems: [GetProductsItem] = [GetProductsItem(productId: subscription.productId,
                                                                          productLabel: subscription.name,
                                                                          billingPeriod: subscription.billingPeriod.rawValue,
                                                                          price: "0.99",
                                                                          currency: "USD")]
    public static let customerPortalURL = GetCustomerPortalURLResponse(customerPortalUrl: "https://duckduckgo.com")
    public static let entitlements = [Entitlement(product: .dataBrokerProtection),
                                      Entitlement(product: .identityTheftRestoration),
                                      Entitlement(product: .networkProtection)]
    public static let confirmPurchase = ConfirmPurchaseResponse(email: email,
                                                                entitlements: entitlements,
                                                                subscription: subscription)
    public static let subscriptionEndpointService = SubscriptionEndpointServiceMock(getSubscriptionResult: .success(subscription),
                                                                                    getProductsResult: .success(productsItems),
                                                                                    getCustomerPortalURLResult: .success(customerPortalURL),
                                                                                    confirmPurchaseResult: .success(confirmPurchase))
    public static let authToken = "someAuthToken"

    private static let validateTokenResponse = ValidateTokenResponse(account: ValidateTokenResponse.Account(email: email,
                                                                                                            entitlements: entitlements,
                                                                                                            externalID: UUID().uuidString))
    public static let authEndpointService = AuthEndpointServiceMock(accessTokenResult: .success(AccessTokenResponse(accessToken: "SomeAccessToken")),
                                                                    validateTokenResult: .success(validateTokenResponse),
                                                                    createAccountResult: .success(CreateAccountResponse(authToken: authToken,
                                                                                                                        externalID: "?",
                                                                                                                        status: "?")),
                                                                    storeLoginResult: .success(StoreLoginResponse(authToken: authToken,
                                                                                                                  email: email,
                                                                                                                  externalID: UUID().uuidString,
                                                                                                                  id: 1,
                                                                                                                  status: "?")))

    public static let storePurchaseManager = StorePurchaseManagerMock(purchasedProductIDs: [UUID().uuidString],
                                                                      purchaseQueue: ["?"],
                                                                      areProductsAvailable: true,
                                                                      subscriptionOptionsResult: SubscriptionOptions.empty,
                                                                      syncAppleIDAccountResultError: nil,
                                                                      mostRecentTransactionResult: nil,
                                                                      hasActiveSubscriptionResult: false,
                                                                      purchaseSubscriptionResult: .success("someTransactionJWS"))

    public static let currentEnvironment = SubscriptionEnvironment(serviceEnvironment: .staging,
                                                                   purchasePlatform: .appStore)

    public static let subscriptionManager = SubscriptionManagerMock(accountManager: accountManager,
                                                                    subscriptionEndpointService: subscriptionEndpointService,
                                                                    authEndpointService: authEndpointService,
                                                                    storePurchaseManager: storePurchaseManager,
                                                                    currentEnvironment: currentEnvironment,
                                                                    canPurchase: true)

    public static let appStoreRestoreFlow = AppStoreRestoreFlowMock(restoreAccountFromPastPurchaseResult: .success(Void()))
}
