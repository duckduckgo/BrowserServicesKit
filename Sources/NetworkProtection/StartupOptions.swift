//
//  StartupOptions.swift
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

struct StartupOptions {

    enum StartupMethod: CustomDebugStringConvertible {
        /// Case started up manually from the main app.
        ///
        case manualByMainApp

        /// Started up manually from a Syste provided source: it can be the VPN menu, a CLI command
        /// or the list of VPNs in System Settings.
        ///
        case manualByTheSystem

        /// Started up automatically by on-demand.
        ///
        case automaticOnDemand

        var debugDescription: String {
            switch self {
            case .automaticOnDemand:
                return "automatically by On-Demand"
            case .manualByMainApp:
                return "manually by the main app"
            case .manualByTheSystem:
                return "manually by the system"
            }
        }
    }

    enum Option<T> {
        case set(_ value: T)
        case reset
        case useExisting
    }

    private let log: OSLog
    let startupMethod: StartupMethod
    let simulateError: Bool
    let simulateCrash: Bool
    let simulateMemoryCrash: Bool
    let enableTester: Bool
    let keyValidity: Option<TimeInterval>
    let selectedServer: Option<SelectedNetworkProtectionServer>
    let authToken: Option<String>

    init(options: [String: Any], log: OSLog) {
        self.log = log

        let startupMethod: StartupMethod = {
            if options[NetworkProtectionOptionKey.isOnDemand] as? Bool == true {
                return .automaticOnDemand
            } else if options[NetworkProtectionOptionKey.activationAttemptId] != nil {
                return .manualByMainApp
            } else {
                return .manualByTheSystem
            }
        }()

        self.startupMethod = startupMethod

        simulateError = options[NetworkProtectionOptionKey.tunnelFailureSimulation] as? Bool ?? false
        simulateCrash = options[NetworkProtectionOptionKey.tunnelFatalErrorCrashSimulation] as? Bool ?? false
        simulateMemoryCrash = options[NetworkProtectionOptionKey.tunnelMemoryCrashSimulation] as? Bool ?? false
        enableTester = options[NetworkProtectionOptionKey.connectionTesterEnabled] as? Bool ?? true

        keyValidity = {
            guard let keyValidityString = options[NetworkProtectionOptionKey.keyValidity] as? String else {
                switch startupMethod {
                case .manualByMainApp:
                    return .reset
                default:
                    return .useExisting
                }
            }

            guard let keyValidity = TimeInterval(keyValidityString) else {
                os_log("The key validity startup option cannot be parsed", log: log, type: .error)
                return .useExisting
            }

            return .set(keyValidity)
        }()

        selectedServer = {
            guard let serverName = options[NetworkProtectionOptionKey.selectedServer] as? String else {
                switch startupMethod {
                case .manualByMainApp:
                    return .reset
                default:
                    return .useExisting
                }
            }

            return .set(.endpoint(serverName))
        }()

        authToken = {
            guard let authToken = options[NetworkProtectionOptionKey.authToken] as? String else {
                switch startupMethod {
                case .manualByMainApp:
                    return .reset
                default:
                    return .useExisting
                }
            }

            return .set(authToken)
        }()
    }
}
