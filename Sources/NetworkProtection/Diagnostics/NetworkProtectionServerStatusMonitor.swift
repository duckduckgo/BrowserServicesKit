//
//  NetworkProtectionServerStatusMonitor.swift
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
import Network
import Common
import Combine

public actor NetworkProtectionServerStatusMonitor {

    public enum ServerStatusResult {
        case serverMigrationRequested
        case error(Error)

        var shouldMigrate: Bool {
            switch self {
            case .serverMigrationRequested: return true
            case .error: return false
            }
        }
    }

    private static let monitoringInterval: TimeInterval = .minutes(5)

    private var task: Task<Never, Error>? {
        willSet {
            task?.cancel()
        }
    }

    var isStarted: Bool {
        task?.isCancelled == false
    }

    private let networkClient: NetworkProtectionClient
    private let tokenStore: NetworkProtectionTokenStore

    // MARK: - Init & deinit

    init(networkClient: NetworkProtectionClient, tokenStore: NetworkProtectionTokenStore) {
        self.networkClient = networkClient
        self.tokenStore = tokenStore

        os_log("[+] %{public}@", log: .networkProtectionMemoryLog, type: .debug, String(describing: self))
    }

    deinit {
        task?.cancel()

        os_log("[-] %{public}@", log: .networkProtectionMemoryLog, type: .debug, String(describing: self))
    }

    // MARK: - Start/Stop monitoring

    public func start(serverName: String, callback: @escaping (ServerStatusResult) -> Void) {
        os_log("⚫️ Starting server status monitor for %{public}s", log: .networkProtectionServerStatusMonitorLog, serverName)

        task = Task.periodic(delay: Self.monitoringInterval, interval: Self.monitoringInterval) {
            let result = await self.checkServerStatus(for: serverName)

            switch result {
            case .success(let serverStatus):
                if serverStatus.shouldMigrate {
                    os_log("⚫️ Initiating server migration away from %{public}s", log: .networkProtectionServerStatusMonitorLog, serverName)
                    callback(.serverMigrationRequested)
                } else {
                    os_log("⚫️ No migration requested for %{public}s", log: .networkProtectionServerStatusMonitorLog, serverName)
                }
            case .failure(let error):
                os_log("⚫️ Error retrieving server status: %{public}@", log: .networkProtectionServerStatusMonitorLog, error.localizedDescription)
                callback(.error(error))
            }
        }
    }

    public func stop() {
        os_log("⚫️ Stopping server status monitor", log: .networkProtectionServerStatusMonitorLog)

        task?.cancel()
        task = nil
    }

    // MARK: - Server Status Check

    private func checkServerStatus(for serverName: String) async -> Result<NetworkProtectionServerStatus, NetworkProtectionClientError> {
        guard let accessToken = try? tokenStore.fetchToken() else {
            assertionFailure("Failed to check server status due to lack of access token")
            return .failure(.invalidAuthToken)
        }

        return await networkClient.getServerStatus(authToken: accessToken, serverName: serverName)
    }

}
