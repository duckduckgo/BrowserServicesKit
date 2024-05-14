//
//  ExtensionRequest.swift
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

public enum DebugCommand: Codable {
    case expireRegistrationKey
    case removeSystemExtension
    case removeVPNConfiguration
    case sendTestNotification
    case disableConnectOnDemandAndShutDown
}

public enum ExtensionRequest {
    case changeTunnelSetting(_ change: VPNSettings.Change)
    case debugCommand(_ command: DebugCommand)
    case getTunnelName(completion: (String) -> Void)

    public enum Message: Codable {
        case changeTunnelSetting(_ change: VPNSettings.Change)
        case debugCommand(_ command: DebugCommand)
        case getAdapterInterfaceName
    }

    var message: Message {
        switch self {
        case .changeTunnelSetting(let change):
            return .changeTunnelSetting(change)
        case .debugCommand(let command):
            return .debugCommand(command)
        case .getTunnelName:
            return .getAdapterInterfaceName
        }
    }

    func handleResponse(data: Data?) throws {
        switch self {
        case .changeTunnelSetting,
                .debugCommand:
            // None of these commands handle the response
            return
        case .getTunnelName(let completion):
            let tunnelName = try decodeTunnelName(data)
            completion(tunnelName)
        }
    }

    enum GetTunnelNameError: Error {
        case noData
        case decodingFailed
    }

    func decodeTunnelName(_ data: Data?) throws -> String {
        guard let data else {
            throw GetTunnelNameError.noData
        }

        guard let tunnelName = String(data: data, encoding: .utf8) else {
            throw GetTunnelNameError.decodingFailed
        }

        return tunnelName
    }
}
