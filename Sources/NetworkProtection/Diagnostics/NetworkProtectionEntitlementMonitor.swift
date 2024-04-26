//
//  NetworkProtectionEntitlementMonitor.swift
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
import Common

public actor NetworkProtectionEntitlementMonitor {
    public enum Result {
        case validEntitlement
        case invalidEntitlement
        case error(Error)
    }

    private static let monitoringInterval: TimeInterval = .minutes(20)

    private var task: Task<Never, Error>? {
        willSet {
            task?.cancel()
        }
    }

    var isStarted: Bool {
        task?.isCancelled == false
    }

    // MARK: - Init & deinit

    public init() {
        os_log("[+] %{public}@", log: .networkProtectionMemoryLog, type: .debug, String(describing: self))
    }

    deinit {
        task?.cancel()

        os_log("[-] %{public}@", log: .networkProtectionMemoryLog, type: .debug, String(describing: self))
    }

    // MARK: - Start/Stop monitoring

    public func start(entitlementCheck: @escaping () async -> Swift.Result<Bool, Error>, callback: @escaping (Result) -> Void) {
        os_log("⚫️ Starting entitlement monitor", log: .networkProtectionEntitlementMonitorLog)

        task = Task.periodic(interval: Self.monitoringInterval) {
            let result = await entitlementCheck()
            switch result {
            case .success(let hasEntitlement):
                if hasEntitlement {
                    os_log("⚫️ Valid entitlement", log: .networkProtectionEntitlementMonitorLog)
                    callback(.validEntitlement)
                } else {
                    os_log("⚫️ Invalid entitlement", log: .networkProtectionEntitlementMonitorLog)
                    callback(.invalidEntitlement)
                }
            case .failure(let error):
                os_log("⚫️ Error retrieving entitlement: %{public}@", log: .networkProtectionEntitlementMonitorLog, error.localizedDescription)
                callback(.error(error))
            }
        }
    }

    public func stop() {
        os_log("⚫️ Stopping entitlement monitor", log: .networkProtectionEntitlementMonitorLog)

        task?.cancel() // Just making extra sure in case it's detached
        task = nil
    }
}
