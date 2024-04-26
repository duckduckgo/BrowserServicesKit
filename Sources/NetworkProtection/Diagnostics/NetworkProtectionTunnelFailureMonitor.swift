//
//  NetworkProtectionTunnelFailureMonitor.swift
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
import Network
import NetworkExtension
import Common
import Combine

public actor NetworkProtectionTunnelFailureMonitor {
    public enum Result {
        case failureDetected
        case failureRecovered
        case networkPathChanged(String)

        var threshold: TimeInterval {
            switch self {
            case .failureDetected: // WG handshakes happen every 2 mins, this means we'd miss 2+ handshakes
                return .minutes(5)
            case .failureRecovered:
                return .minutes(2) // WG handshakes happen every 2 mins
            case .networkPathChanged:
                return -1
            }
        }
    }

    private static let monitoringInterval: TimeInterval = .minutes(1)

    private var task: Task<Never, Error>? {
        willSet {
            task?.cancel()
        }
    }

    var isStarted: Bool {
        task?.isCancelled == false
    }

    private weak var tunnelProvider: PacketTunnelProvider?

    private let networkMonitor = NWPathMonitor()

    private var failureReported = false
    private var firstCheckSkipped = false

    // MARK: - Init & deinit

    init(tunnelProvider: PacketTunnelProvider) {
        self.tunnelProvider = tunnelProvider
        self.networkMonitor.start(queue: .global())

        os_log("[+] %{public}@", log: .networkProtectionMemoryLog, type: .debug, String(describing: self))
    }

    deinit {
        task?.cancel()
        networkMonitor.cancel()

        os_log("[-] %{public}@", log: .networkProtectionMemoryLog, type: .debug, String(describing: self))
    }

    // MARK: - Start/Stop monitoring

    func start(callback: @escaping (Result) -> Void) {
        os_log("⚫️ Starting tunnel failure monitor", log: .networkProtectionTunnelFailureMonitorLog)

        failureReported = false
        firstCheckSkipped = false

        networkMonitor.pathUpdateHandler = { path in
            callback(.networkPathChanged(path.anonymousDescription))
        }

        task = Task.periodic(interval: Self.monitoringInterval) { [weak self] in
            await self?.monitorHandshakes(callback: callback)
        }
    }

    func stop() {
        os_log("⚫️ Stopping tunnel failure monitor", log: .networkProtectionTunnelFailureMonitorLog)

        networkMonitor.cancel()
        networkMonitor.pathUpdateHandler = nil

        task?.cancel() // Just making extra sure in case it's detached
        task = nil
    }

    // MARK: - Handshake monitor

    private func monitorHandshakes(callback: @escaping (Result) -> Void) async {
        guard firstCheckSkipped else {
            // Avoid running the first tunnel failure check after startup to avoid reading the first handshake after sleep, which will almost always
            // be out of date. In normal operation, the first check will frequently be 0 as WireGuard hasn't had the chance to handshake yet.
            os_log("⚫️ Skipping first tunnel failure check", log: .networkProtectionTunnelFailureMonitorLog, type: .debug)
            firstCheckSkipped = true
            return
        }

        let mostRecentHandshake = await tunnelProvider?.mostRecentHandshake() ?? 0

        guard mostRecentHandshake > 0 else {
            os_log("⚫️ Got handshake timestamp at or below 0, skipping check", log: .networkProtectionTunnelFailureMonitorLog, type: .debug)
            return
        }

        let difference = Date().timeIntervalSince1970 - mostRecentHandshake
        os_log("⚫️ Last handshake: %{public}f seconds ago", log: .networkProtectionTunnelFailureMonitorLog, type: .debug, difference)

        if difference > Result.failureDetected.threshold, isConnected {
            if failureReported {
                os_log("⚫️ Tunnel failure already reported", log: .networkProtectionTunnelFailureMonitorLog, type: .debug)
            } else {
                os_log("⚫️ Tunnel failure reported", log: .networkProtectionTunnelFailureMonitorLog, type: .debug)
                callback(.failureDetected)
                failureReported = true
            }
        } else if difference <= Result.failureRecovered.threshold, failureReported {
            os_log("⚫️ Tunnel failure recovery", log: .networkProtectionTunnelFailureMonitorLog, type: .debug)
            callback(.failureRecovered)
            failureReported = false
        }
    }

    private var isConnected: Bool {
        let path = networkMonitor.currentPath
        let connectionType = NetworkConnectionType(nwPath: path)

        return [.wifi, .eth, .cellular].contains(connectionType) && path.status == .satisfied
    }
}

extension Network.NWPath {
    /// A description that's safe from a privacy standpoint.
    ///
    /// Ref: https://app.asana.com/0/0/1206712493935053/1206712516729780/f
    ///
    public var anonymousDescription: String {
        var description = "NWPath("

        description += "status: \(status), "

        if #available(iOS 14.2, *), case .unsatisfied = status {
            description += "unsatisfiedReason: \(unsatisfiedReason), "
        }

        let tunnelCount = availableInterfaces.filter { interface in
            interface.type == .other && interface.name.contains("utun")
        }.count

        let dnsCount = availableInterfaces.filter { interface in
            interface.type == .other && interface.name.contains("dns")
        }.count

        description += "mainInterfaceType: \(String(describing: availableInterfaces.first?.type)), "
        description += "tunnelInterfaceCount: \(tunnelCount), "
        description += "dnsInterfaceCount: \(dnsCount)), "
        description += "isConstrained: \(isConstrained ? "true" : "false"), "
        description += "isExpensive: \(isExpensive ? "true" : "false")"
        description += ")"

        return description
    }
}
