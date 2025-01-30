//
//  SubscriptionEnvironment.swift
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
import Networking

public struct SubscriptionEnvironment: Codable {

    public enum ServiceEnvironment: String, Codable {
        case production, staging

        public var url: URL {
            switch self {
            case .production:
                URL(string: "https://subscriptions.duckduckgo.com/api")!
            case .staging:
                URL(string: "https://subscriptions-dev.duckduckgo.com/api")!
            }
        }

        public var description: String {
            "\(rawValue) - \(url.absoluteString)"
        }
    }

    public var authEnvironment: OAuthEnvironment { serviceEnvironment == .production ? .production : .staging }

    public enum PurchasePlatform: String, Codable {
        case appStore, stripe
    }

    public var serviceEnvironment: SubscriptionEnvironment.ServiceEnvironment
    public var purchasePlatform: SubscriptionEnvironment.PurchasePlatform

    public init(serviceEnvironment: SubscriptionEnvironment.ServiceEnvironment, purchasePlatform: SubscriptionEnvironment.PurchasePlatform) {
        self.serviceEnvironment = serviceEnvironment
        self.purchasePlatform = purchasePlatform
    }

    public var description: String {
        "ServiceEnvironment: \(serviceEnvironment.rawValue), PurchasePlatform: \(purchasePlatform.rawValue)"
    }
}
