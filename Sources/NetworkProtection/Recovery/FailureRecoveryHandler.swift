//
//  FailureRecoveryHandler.swift
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

protocol FailureRecoveryHandling {
    func attemptRecovery(
        to lastConnectedServer: NetworkProtectionServer,
        includedRoutes: [IPAddressRange],
        excludedRoutes: [IPAddressRange],
        isKillSwitchEnabled: Bool,
        updateConfig: @escaping (NetworkProtectionDeviceManagement.GenerateTunnelConfigResult) async throws -> Void
    ) async throws
}

enum FailureRecoveryError: Error {
    case noRecoveryNecessary
    case reachedMaximumRetries(lastError: Error)
}

actor FailureRecoveryHandler: FailureRecoveryHandling {

    struct RetryConfig {
        let times: Int
        let initialDelay: TimeInterval
        let maxDelay: TimeInterval
        let factor: Double

        static var `default` = RetryConfig(
            times: 5,
            initialDelay: .seconds(30),
            maxDelay: .minutes(5),
            factor: 2.0
        )
    }

    private let deviceManager: NetworkProtectionDeviceManagement
    private let retryConfig: RetryConfig

    private var task: Task<NetworkProtectionDeviceManagement.GenerateTunnelConfigResult, FailureRecoveryError>? {
        willSet {
            task?.cancel()
        }
    }

    init(deviceManager: NetworkProtectionDeviceManagement, retryConfig: RetryConfig = .default) {
        self.deviceManager = deviceManager
        self.retryConfig = retryConfig
    }

    func attemptRecovery(
        to lastConnectedServer: NetworkProtectionServer,
        includedRoutes: [IPAddressRange],
        excludedRoutes: [IPAddressRange],
        isKillSwitchEnabled: Bool,
        updateConfig: @escaping (NetworkProtectionDeviceManagement.GenerateTunnelConfigResult) async throws -> Void
    ) async throws {
        try await incrementalPeriodicChecks(retryConfig) {
            let result = try await self.makeRecoveryAttempt(
                to: lastConnectedServer,
                includedRoutes: includedRoutes,
                excludedRoutes: excludedRoutes,
                isKillSwitchEnabled: isKillSwitchEnabled
            )
            try await updateConfig(result)
        }
    }

    func stop() {
        task = nil
    }

    private func makeRecoveryAttempt(
        to lastConnectedServer: NetworkProtectionServer,
        includedRoutes: [IPAddressRange],
        excludedRoutes: [IPAddressRange],
        isKillSwitchEnabled: Bool
    ) async throws -> NetworkProtectionDeviceManagement.GenerateTunnelConfigResult {
        let serverSelectionMethod: NetworkProtectionServerSelectionMethod = .failureRecovery(serverName: lastConnectedServer.serverName)
        let configurationResult: NetworkProtectionDeviceManagement.GenerateTunnelConfigResult

        configurationResult = try await deviceManager.generateTunnelConfiguration(
            selectionMethod: serverSelectionMethod,
            includedRoutes: includedRoutes,
            excludedRoutes: excludedRoutes,
            isKillSwitchEnabled: isKillSwitchEnabled,
            regenerateKey: false
        )
        os_log("🟢 Failure recovery fetched new config.", log: .networkProtectionServerFailureRecoveryLog, type: .info)

        let newServer = configurationResult.server

        os_log(
            "🟢 Failure recovery - originalServerName: %{public}s, newServerName: %{public}s, originalAllowedIPs: %{public}s, newAllowedIPs: %{public}s",
            log: .networkProtection,
            type: .info,
            lastConnectedServer.serverName,
            newServer.serverName,
            String(describing: lastConnectedServer.allowedIPs),
            String(describing: newServer.allowedIPs)
        )

        guard lastConnectedServer.shouldReplace(with: newServer) else {
            os_log("🟢 Server failure recovery not necessary.", log: .networkProtectionServerFailureRecoveryLog, type: .info)
            throw FailureRecoveryError.noRecoveryNecessary
        }

        return configurationResult
    }

    private func incrementalPeriodicChecks(
        _ config: RetryConfig,
        action: @escaping () async throws -> Void
    ) async throws {
        let result = Task.detached(priority: .background) {
            var currentDelay = config.initialDelay
            var count = 0
            var lastError: Error
            repeat {
                do {
                    try await action()
                    os_log("🟢 Failure recovery success!", log: .networkProtectionServerFailureRecoveryLog, type: .info)
                    return
                } catch {
                    if case FailureRecoveryError.noRecoveryNecessary = error {
                        throw error
                    }
                    lastError = error
                    os_log("🟢 Failure recovery failed. Retrying...", log: .networkProtectionServerFailureRecoveryLog, type: .info)
                    try? await Task.sleep(interval: currentDelay)
                }
                count += 1
                currentDelay = min((currentDelay * config.factor), config.maxDelay)
            } while count < config.times

            throw FailureRecoveryError.reachedMaximumRetries(lastError: lastError)
        }
        try await result.value
    }
}

private extension NetworkProtectionServer {
    func shouldReplace(with newServer: NetworkProtectionServer) -> Bool {
        guard serverName == newServer.serverName else {
            return true
        }

        guard let lastAllowedIPs = allowedIPs,
              let newAllowedIPs = newServer.allowedIPs,
              Set(lastAllowedIPs) == Set(newAllowedIPs) else {
            return true
        }

        return false
    }
}
