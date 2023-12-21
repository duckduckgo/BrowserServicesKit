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

        var threshold: TimeInterval {
            switch self {
            case .failureDetected: // WG handshakes happen every 2 mins, this means we'd miss 2+ handshakes
                return .minutes(5)
            case .failureRecovered:
                return .minutes(2) // WG handshakes happen every 2 mins
            }
        }
    }

    private static let monitoringInterval: TimeInterval = .seconds(10)

    @MainActor
    private var task: Task<Never, Error>? {
        willSet {
            task?.cancel()
        }
    }

    @MainActor
    var isStarted: Bool {
        task?.isCancelled == false
    }

    private let tunnelProvider: PacketTunnelProvider
    private let networkMonitor = NWPathMonitor()

    private let log: OSLog

    @MainActor
    private var failureReported = false

    // MARK: - Init & deinit

    init(tunnelProvider: PacketTunnelProvider, log: OSLog) {
        self.tunnelProvider = tunnelProvider
        self.log = log

        os_log("[+] %{public}@", log: .networkProtectionMemoryLog, type: .debug, String(describing: self))
    }

    deinit {
        os_log("[-] %{public}@", log: .networkProtectionMemoryLog, type: .debug, String(describing: self))
    }

    // MARK: - Start/Stop monitoring

    @MainActor
    func start(callback: @escaping (Result) -> Void) {
        os_log("⚫️ Starting tunnel failure monitor", log: log)

        failureReported = false
        networkMonitor.start(queue: .global())

        task = Task.periodic(interval: Self.monitoringInterval) { [weak self] in
            await self?.monitorHandshakes(callback: callback)
        }
    }

    @MainActor
    func stop() {
        os_log("⚫️ Stopping tunnel failure monitor", log: log)

        task = nil
        networkMonitor.cancel()
    }

    // MARK: - Handshake monitor

    @MainActor
    private func monitorHandshakes(callback: @escaping (Result) -> Void) async {
        let mostRecentHandshake = await tunnelProvider.mostRecentHandshake() ?? 0

        let difference = Date().timeIntervalSince1970 - mostRecentHandshake
        os_log("⚫️ Last handshake: %{public}f seconds ago", log: .networkProtectionPixel, type: .debug, difference)

        if difference > Result.failureDetected.threshold, isConnected {
            if failureReported {
                os_log("⚫️ Tunnel failure already reported", log: .networkProtectionPixel, type: .debug)
            } else {
                callback(.failureDetected)
                failureReported = true
            }
        } else if difference <= Result.failureRecovered.threshold, failureReported {
            callback(.failureRecovered)
            failureReported = false
        }
    }

    @MainActor
    private var isConnected: Bool {
        let path = networkMonitor.currentPath
        let connectionType = NetworkConnectionType(nwPath: path)

        return [.wifi, .eth, .cellular].contains(connectionType) && path.status == .satisfied
    }
}
