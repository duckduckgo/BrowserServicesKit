//
//  NetworkProtectionNotificationsSettingsStore.swift
//  DuckDuckGo
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

final public class NetworkProtectionNotificationsSettingsStore {
    private enum Key {
        static let alerts = "com.duckduckgo.notificationSettings.alertsEnabled"
    }

    private static let alertsEnabledKey = "com.duckduckgo.notificationSettings"
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    var alertsEnabled: Bool {
        get {
            guard self.userDefaults.object(forKey: Key.alerts) != nil else {
                return true
            }
            return self.userDefaults.bool(forKey: Key.alerts)
        }
        set {
            self.userDefaults.set(newValue, forKey: Key.alerts)
        }
    }
}
