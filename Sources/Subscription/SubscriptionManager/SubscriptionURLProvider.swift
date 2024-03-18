//
//  SubscriptionURLProvider.swift
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

public protocol SubscriptionURLProviding {
    func url(for type: SubscriptionURLType) -> URL
}

public final class SubscriptionURLProvider: SubscriptionURLProviding {

    private let configuration: SubscriptionConfiguration

    init(configuration: SubscriptionConfiguration) {
        self.configuration = configuration
    }

    public func url(for type: SubscriptionURLType) -> URL {
        var url = type.url

        if configuration.currentServiceEnvironment == .staging {
            url = url.appendingParameter(name: "environment", value: "staging")
        }

        return url
    }
}

public enum SubscriptionURLType {
    case purchase
    case welcome
    case activateWithEmail
    case activateWithEmailSuccess
    case addEmail
    case manageEmail
    case identityTheftRestoration

    public var url: URL {
        switch self {
        case .purchase:
            URL.subscriptionBaseURL
        case .welcome:
            URL.subscriptionBaseURL.appendingPathComponent("welcome")
        case .activateWithEmail:
            URL.subscriptionBaseURL.appendingPathComponent("activate")
        case .activateWithEmailSuccess:
            URL.subscriptionBaseURL.appendingPathComponent("activate/success")
        case .addEmail:
            URL.subscriptionBaseURL.appendingPathComponent("add-email")
        case .manageEmail:
            URL.subscriptionBaseURL.appendingPathComponent("manage")
        case .identityTheftRestoration:
            URL.identityTheftRestorationBaseURL
        }
    }
}

public extension URL {

    static var subscriptionBaseURL: URL {
        URL(string: "https://duckduckgo.com/subscriptions")!
    }

    static var identityTheftRestorationBaseURL: URL {
        URL(string: "https://duckduckgo.com/identity-theft-restoration")!
    }

    static var subscriptionFAQ: URL {
        URL(string: "https://duckduckgo.com/duckduckgo-help-pages/privacy-pro/")!
    }

    static var manageSubscriptionsInAppStoreAppURL: URL {
        URL(string: "macappstores://apps.apple.com/account/subscriptions")!
    }
}

public extension URL {

    enum Constants {
        static let paramNameEnvironment = "environment"
        static let paramValueEnvironmentStaging = "staging"
    }

    func appendingSubscriptionEnvironmentParameter(environment: SubscriptionServiceEnvironment) -> URL {
        var updatedURL: URL

        switch environment {
        case .production:
            updatedURL = self.removingSubscriptionEnvironmentParameter()
        case .staging:
            updatedURL = self.removingSubscriptionEnvironmentParameter()
            updatedURL = updatedURL.appendingParameter(name: Constants.paramNameEnvironment,
                                                       value: Constants.paramValueEnvironmentStaging)
        }

        return updatedURL
    }

    func removingSubscriptionEnvironmentParameter() -> URL {
        guard self.getParameter(named: Constants.paramNameEnvironment) != nil else { return self }
        return removingParameters(named: [Constants.paramNameEnvironment])
    }
}

