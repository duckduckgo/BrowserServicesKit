//
//  NetworkProtectionSnoozeTimingStore.swift
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

final public class NetworkProtectionSnoozeTimingStore {

    public struct SnoozeTiming: Codable, Equatable {
        let startDate: Date
        let duration: TimeInterval

        var endDate: Date {
            return startDate.addingTimeInterval(duration)
        }
    }

    private static let activeSnoozeTimingKey = "com.duckduckgo.NetworkProtectionSnoozeTimingStore.activeTiming"

    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter

    public init(userDefaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
    }

    public var activeTiming: SnoozeTiming? {
        get {
            guard let data = userDefaults.data(forKey: Self.activeSnoozeTimingKey) else { return nil }
            return try? JSONDecoder().decode(SnoozeTiming.self, from: data)
        }

        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: Self.activeSnoozeTimingKey)
            } else {
                userDefaults.removeObject(forKey: Self.activeSnoozeTimingKey)
            }

            notificationCenter.post(name: .snoozeDidChange, object: nil)
        }
    }

    public func reset() {
        activeTiming = nil
    }

}

extension NSNotification.Name {

    static let snoozeDidChange: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.browserServicesKit.vpn.snoozeDidChange")

}
