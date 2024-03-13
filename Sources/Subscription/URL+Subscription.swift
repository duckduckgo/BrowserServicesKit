//
//  URL+Subscription.swift
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
import Macros

public extension URL {

    static var subscriptionBaseURL: URL {
        switch SubscriptionPurchaseEnvironment.currentServiceEnvironment {
        case .production:
            #URL("https://duckduckgo.com/subscriptions")
        case .staging:
            #URL("https://duckduckgo.com/subscriptions?environment=staging")
        }
    }

    static var subscriptionPurchase: URL {
        subscriptionBaseURL.appendingPathComponent("welcome")
    }

    static var subscriptionFAQ: URL {
        #URL("https://duckduckgo.com/duckduckgo-help-pages/privacy-pro/")
    }

    // MARK: - Subscription Email
    static var activateSubscriptionViaEmail: URL {
        subscriptionBaseURL.appendingPathComponent("activate")
    }

    static var addEmailToSubscription: URL {
        subscriptionBaseURL.appendingPathComponent("add-email")
    }

    static var manageSubscriptionEmail: URL {
        subscriptionBaseURL.appendingPathComponent("manage")
    }

    // MARK: - App Store app manage subscription URL

    static var manageSubscriptionsInAppStoreAppURL: URL {
        #URL("macappstores://apps.apple.com/account/subscriptions")
    }

    // MARK: - Identity Theft Restoration

    static var identityTheftRestoration: URL {
        switch SubscriptionPurchaseEnvironment.currentServiceEnvironment {
        case .production:
            #URL("https://duckduckgo.com/identity-theft-restoration")
        case .staging:
            #URL("https://duckduckgo.com/identity-theft-restoration?environment=staging")
        }
    }
}
