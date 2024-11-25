//
//  StoreSubscriptionConfiguration.swift
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
import Combine

protocol StoreSubscriptionConfiguration {
    var allSubscriptionIdentifiers: [String] { get }
    func subscriptionIdentifiers(for country: String) -> [String]
}

final class DefaultStoreSubscriptionConfiguration: StoreSubscriptionConfiguration {

    private let subscriptions: [StoreSubscriptionDefinition]

    convenience init() {
        self.init(subscriptionDefinitions: [
            // Production shared for iOS and macOS
            .init(name: "DuckDuckGo Private Browser",
                  appIdentifier: "com.duckduckgo.mobile.ios",
                  environment: .production,
                  identifiersByCountries: [.usa: ["ddg.privacy.pro.monthly.renews.us",
                                                  "ddg.privacy.pro.yearly.renews.us"]]),
            // iOS debug Alpha build
            .init(name: "DuckDuckGo Alpha",
                  appIdentifier: "com.duckduckgo.mobile.ios.alpha",
                  environment: .staging,
                  identifiersByCountries: [.usa: ["ios.subscription.1month",
                                                  "ios.subscription.1year"],
                                           .restOfWorld: ["ios.subscription.1month.row",
                                                          "ios.subscription.1year.row"]]),
            // macOS debug build
            .init(name: "IAP debug - DDG for macOS",
                  appIdentifier: "com.duckduckgo.macos.browser.debug",
                  environment: .staging,
                  identifiersByCountries: [.usa: ["subscription.1month",
                                                  "subscription.1year"],
                                           .restOfWorld: ["subscription.1month.row",
                                                          "subscription.1year.row"]]),
            // macOS review build
            .init(name: "IAP review - DDG for macOS",
                  appIdentifier: "com.duckduckgo.macos.browser.review",
                  environment: .staging,
                  identifiersByCountries: [.usa: ["review.subscription.1month",
                                                  "review.subscription.1year"],
                                           .restOfWorld: ["review.subscription.1month.row",
                                                          "review.subscription.1year.row"]]),

            // macOS TestFlight build
            .init(name: "DuckDuckGo Sandbox Review",
                  appIdentifier: "com.duckduckgo.mobile.ios.review",
                  environment: .staging,
                  identifiersByCountries: [.usa: ["tf.sandbox.subscription.1month",
                                                  "tf.sandbox.subscription.1year"],
                                           .restOfWorld: ["tf.sandbox.subscription.1month.row",
                                                          "tf.sandbox.subscription.1year.row"]])
        ])
    }

    init(subscriptionDefinitions: [StoreSubscriptionDefinition]) {
        self.subscriptions = subscriptionDefinitions
    }

    var allSubscriptionIdentifiers: [String] {
        subscriptions.reduce([], { $0 + $1.allIdentifiers() })
    }

    func subscriptionIdentifiers(for country: String) -> [String] {
        subscriptions.reduce([], { $0 + $1.identifiers(for: country) })
    }
}

struct StoreSubscriptionDefinition {
    var name: String
    var appIdentifier: String
    var environment: SubscriptionEnvironment.ServiceEnvironment
    var identifiersByCountries: [SubscriptionRegion: [String]]

    func allIdentifiers() -> [String] {
        identifiersByCountries.values.flatMap { $0 }
    }

    func identifiers(for country: String) -> [String] {
        identifiersByCountries.filter { countries, _ in countries.contains(country) }.flatMap { _, identifiers in identifiers }
    }
}

public enum SubscriptionRegion: CaseIterable {
    case usa
    case restOfWorld
    
    /// Country codes as used by StoreKit, in the ISO 3166-1 Alpha-3 country code representation
    /// .restOfWorld defined based on https://app.asana.com/0/1208524871249522/1208571752166956/f
    var countryCodes: Set<String> {
        switch self {
        case .usa:
            return Set(["USA"])
        case .restOfWorld:
            return Set(["CAN", "GBR", "AUT", "DEU", "NLD", "POL", "SWE",
                        "BEL", "BGR", "HRV ", "CYP", "CZE", "DNK", "EST", "FIN", "FRA", "GRC", "HUN", "IRL", "ITA", "LVA", "LTU", "LUX", "MLT", "PRT",
                        "ROU", "SVK", "SVN", "ESP"])
        }
    }

    func contains(_ country: String) -> Bool {
        countryCodes.contains(country.uppercased())
    }

    static func matchingRegion(for countryCode: String) -> Self? {
        Self.allCases.first { $0.countryCodes.contains(countryCode) }
    }
}
