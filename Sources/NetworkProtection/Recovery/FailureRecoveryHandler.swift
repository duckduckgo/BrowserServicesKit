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
        regenerateKey: Bool
    ) async throws -> (tunnelConfig: TunnelConfiguration, server: NetworkProtectionServer)
}

enum FailureRecoveryError: Error {
    case noRecoveryNecessary
    case configGenerationError(NetworkProtectionError)
}

struct FailureRecoveryHandler: FailureRecoveryHandling {

    private let deviceManager: NetworkProtectionDeviceManagement

    init(deviceManager: NetworkProtectionDeviceManagement) {
        self.deviceManager = deviceManager
    }

    func attemptRecovery(
        to lastConnectedServer: NetworkProtectionServer,
        includedRoutes: [IPAddressRange],
        excludedRoutes: [IPAddressRange],
        isKillSwitchEnabled: Bool,
        regenerateKey: Bool
    ) async throws -> (tunnelConfig: TunnelConfiguration, server: NetworkProtectionServer) {
        let serverSelectionMethod: NetworkProtectionServerSelectionMethod = .failureRecovery(serverName: lastConnectedServer.serverName)
        let configurationResult: (tunnelConfig: TunnelConfiguration, server: NetworkProtectionServer)

        do {
            configurationResult = try await deviceManager.generateTunnelConfiguration(
                selectionMethod: serverSelectionMethod,
                includedRoutes: includedRoutes,
                excludedRoutes: excludedRoutes,
                isKillSwitchEnabled: isKillSwitchEnabled,
                regenerateKey: regenerateKey
            )
            os_log("🟢 Failure recovery fetched new config.", log: .networkProtectionServerFailureRecoveryLog, type: .info)
        } catch let error as NetworkProtectionError {
            os_log("🟢 Failure recovery config generation failed.", log: .networkProtectionServerFailureRecoveryLog, type: .info)
            throw FailureRecoveryError.configGenerationError(error)
        } catch {
            os_log("🟢 Failure recovery config generation failed.", log: .networkProtectionServerFailureRecoveryLog, type: .info)
            throw NetworkProtectionError.unhandledError(function: #function, line: #line, error: error)
        }

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
