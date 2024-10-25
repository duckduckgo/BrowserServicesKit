//
//  SubscriptionManagerMock.swift
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

public final class SubscriptionManagerMock: SubscriptionManager {

    public var subscriptionEndpointService: SubscriptionEndpointService
    let internalStorePurchaseManager: StorePurchaseManager
    public static var storedEnvironment: SubscriptionEnvironment?

    public static func loadEnvironmentFrom(userDefaults: UserDefaults) -> SubscriptionEnvironment? {
        return storedEnvironment
    }

    public static func save(subscriptionEnvironment: SubscriptionEnvironment, userDefaults: UserDefaults) {
        storedEnvironment = subscriptionEnvironment
    }

    public var currentEnvironment: SubscriptionEnvironment
    public var canPurchase: Bool = true

    public func storePurchaseManager() -> StorePurchaseManager {
        internalStorePurchaseManager
    }

    public func refreshCachedSubscription(completion: @escaping (Bool) -> Void) {
        completion(true)
    }

    public func url(for type: SubscriptionURL) -> URL {
        type.subscriptionURL(environment: currentEnvironment.serviceEnvironment)
    }

    // MARK: -
}
