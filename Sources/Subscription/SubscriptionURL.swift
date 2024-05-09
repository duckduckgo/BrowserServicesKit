//
//  SubscriptionURL.swift
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

extension URL {
    
    public func forComparison() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }

        if let queryItems = components.queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems.filter { !["environment"].contains($0.name) }

            if components.queryItems?.isEmpty ?? true {
                components.queryItems = nil
            }
        } else {
            components.queryItems = nil
        }
        return components.url ?? self
    }
}
