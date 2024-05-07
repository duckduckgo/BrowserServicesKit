//
//  SubscriptionManager.swift
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
import Common
import PixelKit

public struct SubscriptionEnvironment {

    public enum ServiceEnvironment: String, Codable {
        case production
        case staging

        public static var `default`: ServiceEnvironment = .production

        public var description: String {
            switch self {
            case .production: return "Production"
            case .staging: return "Staging"
            }
        }
    }

    public enum Platform: String {
        case appStore, stripe
    }

    public var serviceEnvironment: ServiceEnvironment
    public var platform: Platform
}

// MARK: - URLs, ex URL+Subscription

public enum SubscriptionURL {
    case baseURL
    case purchase
    case FAQ
    case activateViaEmail
    case addEmail
    case manageEmail
    case activateSuccess
    case addEmailToSubscriptionSuccess
    case addEmailToSubscriptionOTP
    case manageSubscriptionsInAppStore
    case identityTheftRestoration

    public func subscriptionURL(environment: SubscriptionEnvironment.ServiceEnvironment) -> URL {
        switch self {
        case .baseURL:
            switch environment {
            case .production:
                URL(string: "https://duckduckgo.com/subscriptions")!
            case .staging:
                URL(string: "https://duckduckgo.com/subscriptions?environment=staging")!
            }
        case .purchase:
            SubscriptionURL.baseURL.subscriptionURL(environment: environment).appendingPathComponent("welcome")
        case .FAQ:
            URL(string: "https://duckduckgo.com/duckduckgo-help-pages/privacy-pro/")!
        case .activateViaEmail:
            SubscriptionURL.baseURL.subscriptionURL(environment: environment).appendingPathComponent("activate")
        case .addEmail:
            SubscriptionURL.baseURL.subscriptionURL(environment: environment).appendingPathComponent("add-email")
        case .manageEmail:
            SubscriptionURL.baseURL.subscriptionURL(environment: environment).appendingPathComponent("manage")
        case .activateSuccess:
            SubscriptionURL.baseURL.subscriptionURL(environment: environment).appendingPathComponent("activate/success")
        case .addEmailToSubscriptionSuccess:
            SubscriptionURL.baseURL.subscriptionURL(environment: environment).appendingPathComponent("add-email/success")
        case .addEmailToSubscriptionOTP:
            SubscriptionURL.baseURL.subscriptionURL(environment: environment).appendingPathComponent("add-email/otp")
        case .manageSubscriptionsInAppStore:
            URL(string: "macappstores://apps.apple.com/account/subscriptions")!
        case .identityTheftRestoration:
            switch environment {
            case .production:
                URL(string: "https://duckduckgo.com/identity-theft-restoration")!
            case .staging:
                URL(string: "https://duckduckgo.com/identity-theft-restoration?environment=staging")!
            }
        }
    }
}

/// Single entry point for everything related to Subscription. This manager is disposable, every time something related to the environment changes this need to be recreated.
final public class SubscriptionManager {

    let storePurchaseManager: StorePurchaseManaging?
    public let accountManager: AccountManaging

    public let subscriptionService: SubscriptionService
    public let authService: AuthService
    
    public init(storePurchaseManager: StorePurchaseManaging? = nil,
                accountManager: AccountManaging,
                subscriptionService: SubscriptionService,
                authService: AuthService,
                currentServiceEnvironment: SubscriptionEnvironment.ServiceEnvironment = .default,
                current: SubscriptionEnvironment.Platform = .appStore) {
        self.storePurchaseManager = storePurchaseManager
        self.accountManager = accountManager
        self.subscriptionService = subscriptionService
        self.authService = authService
        self.currentEnvironment = SubscriptionEnvironment(serviceEnvironment: currentServiceEnvironment,
                                                          platform: current)
        switch current {
        case .appStore:
            if #available(macOS 12.0, iOS 15.0, *) {
                setupForAppStore()
            }
        case .stripe:
            setupForStripe()
        }
    }

    @available(macOS 12.0, iOS 15.0, *) public func getStorePurchaseManager() -> StorePurchaseManaging {
        return storePurchaseManager!
    }

    // MARK: - Environment, ex SubscriptionPurchaseEnvironment

    public let currentEnvironment: SubscriptionEnvironment
    public private(set) var canPurchase: Bool = false

    @available(macOS 12.0, iOS 15.0, *) private func setupForAppStore() {
        Task {
            await storePurchaseManager?.updateAvailableProducts()
            if let storePurchaseManager {
                canPurchase = !storePurchaseManager.areProductsAvailable
            } else {
                canPurchase = false
            }
        }
    }

    private func setupForStripe() {
        Task {
            if case let .success(products) = await subscriptionService.getProducts() {
                canPurchase = !products.isEmpty
            }
        }
    }

    // MARK: -

    public func loadInitialData() {
        Task {
            if let token = accountManager.accessToken {
                _ = await subscriptionService.getSubscription(accessToken: token, cachePolicy: .reloadIgnoringLocalCacheData)
                _ = await accountManager.fetchEntitlements(cachePolicy: .reloadIgnoringLocalCacheData)
            }
        }
    }

    public func updateSubscriptionStatus(completion: @escaping (_ isActive: Bool) -> Void) {
        Task {
           guard let token = accountManager.accessToken else { return }

            if case .success(let subscription) = await subscriptionService.getSubscription(accessToken: token, cachePolicy: .reloadIgnoringLocalCacheData) {
                completion(subscription.isActive)
            }

            _ = await accountManager.fetchEntitlements(cachePolicy: .reloadIgnoringLocalCacheData)
        }
    }
}
