//
//  SubscriptionFeatureAvailability.swift
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
import Subscription

public protocol SubscriptionFeatureAvailability {
    var isFeatureAvailable: Bool { get }
    var isSubscriptionPurchaseAllowed: Bool { get }
}

public final class DefaultSubscriptionFeatureAvailability: SubscriptionFeatureAvailability {

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let subscriptionPlatform: SubscriptionEnvironment.Platform

    public init(privacyConfigurationManager: PrivacyConfigurationManaging, subscriptionPlatform: SubscriptionEnvironment.Platform) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.subscriptionPlatform = subscriptionPlatform
    }

    public var isFeatureAvailable: Bool {
        isInternalUser || isSubscriptionLaunched || isSubscriptionLaunchedOverride
    }

    public var isSubscriptionPurchaseAllowed: Bool {
        let isPurchaseAllowed: Bool

        switch subscriptionPlatform {
        case .appStore:
            isPurchaseAllowed = privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchase)
        case .stripe:
            isPurchaseAllowed = privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchaseStripe)
        }

        return isPurchaseAllowed || isInternalUser
    }

// MARK: - Conditions

    private var isInternalUser: Bool {
        privacyConfigurationManager.internalUserDecider.isInternalUser
    }

    private var isSubscriptionLaunched: Bool {
        switch subscriptionPlatform {
        case .appStore:
            privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunched)
        case .stripe:
            privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedStripe)
        }
    }

    private var isSubscriptionLaunchedOverride: Bool {
        switch subscriptionPlatform {
        case .appStore:
            privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedOverride)
        case .stripe:
            privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedOverrideStripe)
        }
    }
}
