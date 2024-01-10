//
//  NetworkProtectionTunnelHealthStore.swift
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
import Network

/// Stores information about NetP's tunnel health
///
public final class NetworkProtectionTunnelHealthStore {
    private static let isHavingConnectivityIssuesKey = "com.duckduckgo.isHavingConnectivityIssues"
    private static let lastNetworkPathChangeDate = "com.duckduckgo.lastNetworkPathChangeDate"
    private static let previousNetworkPath = "com.duckduckgo.previousNetworkPath"
    private static let currentNetworkPath = "com.duckduckgo.currentNetworkPath"
    private let userDefaults: UserDefaults

#if os(macOS)

    private let notificationCenter: NetworkProtectionNotificationCenter

    public init(userDefaults: UserDefaults = .standard,
                notificationCenter: NetworkProtectionNotificationCenter) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
    }

    // MARK: - Posting Issue Notifications

    private func postIssueChangeNotification(newValue: Bool) {
        if newValue {
            notificationCenter.post(.issuesStarted)
        } else {
            notificationCenter.post(.issuesResolved)
        }
    }

#else

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

#endif

    var isHavingConnectivityIssues: Bool {
        get {
            userDefaults.bool(forKey: Self.isHavingConnectivityIssuesKey)
        }

        set {
            guard newValue != userDefaults.bool(forKey: Self.isHavingConnectivityIssuesKey) else {
                return
            }
            userDefaults.set(newValue, forKey: Self.isHavingConnectivityIssuesKey)
            os_log("Issues set to %{public}@", log: .networkProtectionConnectionTesterLog, String(reflecting: newValue))
#if os(macOS)
            postIssueChangeNotification(newValue: newValue)
#endif
        }
    }

    public var lastNetworkPathChangeDate: Date {
        (userDefaults.object(forKey: Self.lastNetworkPathChangeDate) as? Date) ?? .distantPast
    }

    public var lastNetworkPathChange: String {
        let previousNetworkPath = userDefaults.object(forKey: Self.previousNetworkPath) ?? "undefined"
        let currentNetworkPath = userDefaults.object(forKey: Self.currentNetworkPath) ?? "undefined"
        return "\(previousNetworkPath) -> \(currentNetworkPath)"
    }

    public func updateNetworkPath(_ path: NWPath?, updatesTimestamp: Bool = true) {
        let currentNetworkPath = (userDefaults.object(forKey: Self.currentNetworkPath) as? String) ?? "undefined"
        guard let newNetworkPath = path?.debugDescription, newNetworkPath != currentNetworkPath else { return }

        userDefaults.set(currentNetworkPath, forKey: Self.previousNetworkPath)
        userDefaults.set(newNetworkPath, forKey: Self.currentNetworkPath)

        if updatesTimestamp {
            userDefaults.set(Date(), forKey: Self.lastNetworkPathChangeDate)
        }

        os_log("⚫️ Network path change: %{public}@", log: .networkProtectionTunnelFailureMonitorLog, type: .debug, lastNetworkPathChange)
    }
}
