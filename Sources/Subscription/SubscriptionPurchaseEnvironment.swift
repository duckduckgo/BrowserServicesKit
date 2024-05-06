//
//  SubscriptionPurchaseEnvironment.swift
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
import Common

public final class SubscriptionPurchaseEnvironment {

    let subscriptionService: SubscriptionService

    init(subscriptionService: SubscriptionService) {
        self.subscriptionService = subscriptionService
    }

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

    public var currentServiceEnvironment: ServiceEnvironment = .default

    public enum Environment: String {
        case appStore, stripe
    }

    public var current: Environment = .appStore {
        didSet {
            os_log(.info, log: .subscription, "[SubscriptionPurchaseEnvironment] Setting to %{public}s", current.rawValue)

            canPurchase = false

            switch current {
            case .appStore:
                setupForAppStore()
            case .stripe:
                setupForStripe()
            }
        }
    }

    public var canPurchase: Bool = false {
        didSet {
            os_log(.info, log: .subscription, "[SubscriptionPurchaseEnvironment] canPurchase %{public}s", (canPurchase ? "true" : "false"))
        }
    }

    private func setupForAppStore() {
        if #available(macOS 12.0, iOS 15.0, *) {
            Task {
                await StorePurchaseManager.shared.updateAvailableProducts()
                canPurchase = !StorePurchaseManager.shared.availableProducts.isEmpty
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
}
