//
//  SubscriptionConfiguration.swift
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

public protocol SubscriptionConfiguration {
    var currentPurchasePlatform: SubscriptionPurchasePlatform { get }
}

public enum SubscriptionPurchasePlatform: String {
    case appStore, stripe
}

public final class DefaultSubscriptionConfiguration: SubscriptionConfiguration {

    public private(set) var currentPurchasePlatform: SubscriptionPurchasePlatform {
        didSet {
            os_log(.info, log: .subscription, "[DefaultSubscriptionConfiguration] Setting to %{public}s", currentPurchasePlatform.rawValue)

            if currentPurchasePlatform == .appStore {
                setupForAppStore()
            }
        }
    }

    public init(currentPurchasePlatform: SubscriptionPurchasePlatform) {
        self.currentPurchasePlatform = currentPurchasePlatform
    }

    private func setupForAppStore() {
        if #available(macOS 12.0, iOS 15.0, *) {
            Task {
                await PurchaseManager.shared.updateAvailableProducts()
            }
        }
    }
}

// MARK: - Debug

public protocol DebugSubscriptionConfiguration {
    func updateCurrentPurchasePlatform(to platform: SubscriptionPurchasePlatform)
}

extension DefaultSubscriptionConfiguration: DebugSubscriptionConfiguration {
    public func updateCurrentPurchasePlatform(to platform: SubscriptionPurchasePlatform) {
        self.currentPurchasePlatform = platform
    }
}
