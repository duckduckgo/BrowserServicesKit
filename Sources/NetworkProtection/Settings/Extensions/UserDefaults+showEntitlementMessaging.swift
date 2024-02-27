//
//  UserDefaults+showEntitlementMessaging.swift
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
import Common

extension UserDefaults {
    private var showEntitlementAlertKey: String {
        "networkProtectionShowEntitlementAlertRawValue"
    }

    @objc
    dynamic var showEntitlementAlert: Bool {
        get {
            value(forKey: showEntitlementAlertKey) as? Bool ?? false
        }

        set {
            set(newValue, forKey: showEntitlementAlertKey)
        }
    }

    var showEntitlementAlertPublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.showEntitlementAlert).eraseToAnyPublisher()
    }

    private var showEntitlementNotificationKey: String {
        "networkProtectionShowEntitlementNotificationRawValue"
    }

    @objc
    dynamic var showEntitlementNotification: Bool {
        get {
            value(forKey: showEntitlementNotificationKey) as? Bool ?? false
        }

        set {
            set(newValue, forKey: showEntitlementNotificationKey)
        }
    }

    var showEntitlementNotificationPublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.showEntitlementNotification).eraseToAnyPublisher()
    }

    func resetEntitlementMessaging() {
        removeObject(forKey: showEntitlementAlertKey)
        removeObject(forKey: showEntitlementNotificationKey)
    }
}
