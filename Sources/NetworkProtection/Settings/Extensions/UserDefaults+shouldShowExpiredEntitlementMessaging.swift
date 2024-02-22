//
//  UserDefaults+shouldShowExpiredEntitlementMessaging.swift
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

import Combine
import Foundation

extension UserDefaults {
    /// Whether to show the expired entitlement messaging
    /// - showsAlert: Show the in-app alert
    /// - showsNotification: Show the banner notification
    /// 
    /// Possible states:
    ///   1. `nil` -> Nothing to show (either the user doesn't have a subscription, or they currently have a valid one)
    ///   2. `(showsAlert: true, showsNotification: true)` -> Needs to show expired entitlement messaging.
    ///   2b. `(showsAlert: true, showsNotification: false)` -> Notification already shown, needs to show alert.
    ///   2c. `(showsAlert: false, showsNotification: true)` -> Alert already shown, needs to show notification.
    ///   3. `(showsAlert: false, showsNotification: false)` -> Expired entitlement messaging already shown.
    ///
    /// Valid transitions: 1 -> 2 -> 2a/2b -> 3 -> 1
    /// Messaging isn't shown more than once so something like 3/2a/2b -> 2 isn't a valid transition.
    public final class ExpiredEntitlementMessaging: NSObject, Codable {
        public let showsAlert: Bool
        public let showsNotification: Bool

        public init(showsAlert: Bool = false, showsNotification: Bool = false) {
            self.showsAlert = showsAlert
            self.showsNotification = showsNotification
        }
    }

    private var shouldShowExpiredEntitlementMessagingKey: String {
        "shouldShowExpiredEntitlementMessaging"
    }

    @objc
    dynamic var shouldShowExpiredEntitlementMessaging: ExpiredEntitlementMessaging? {
        get {
            guard let data = data(forKey: shouldShowExpiredEntitlementMessagingKey),
                  let value = try? JSONDecoder().decode(ExpiredEntitlementMessaging.self, from: data) else {
                return nil
            }
            return value
        }

        set {
            // Messaging already queued, skip
            if let newValue, newValue.showsAlert, newValue.showsNotification,
               shouldShowExpiredEntitlementMessaging != nil {
                return
            }

            guard let data = try? JSONEncoder().encode(newValue) else { return }
            set(data, forKey: shouldShowExpiredEntitlementMessagingKey)
        }
    }

    var shouldShowExpiredEntitlementMessagingPublisher: AnyPublisher<ExpiredEntitlementMessaging?, Never> {
        publisher(for: \.shouldShowExpiredEntitlementMessaging).eraseToAnyPublisher()
    }
}
