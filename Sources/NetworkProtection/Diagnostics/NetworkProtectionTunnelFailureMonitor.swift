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

final public class NetworkProtectionTunnelFailureMonitor {
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

    public var publisher: AnyPublisher<Result, Never> {
        failureSubject.eraseToAnyPublisher()
    }
    private let failureSubject = PassthroughSubject<Result, Never>()

    private actor TimerRunCoordinator {
        private(set) var isRunning = false

        func start() {
            isRunning = true
        }

        func stop() {
            isRunning = false
        }
    }

    private var timer: DispatchSourceTimer?
    private let timerRunCoordinator = TimerRunCoordinator()
    private let timerQueue: DispatchQueue

    private let tunnelProvider: PacketTunnelProvider
    private let networkMonitor = NWPathMonitor()

    private let log: OSLog

    private let lock = NSLock()

    private var _failureReported = false
    private(set) var failureReported: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _failureReported
        }
        set {
            lock.lock()
            self._failureReported = newValue
            lock.unlock()
        }
    }

    // MARK: - Init & deinit

    init(tunnelProvider: PacketTunnelProvider, timerQueue: DispatchQueue, log: OSLog) {
        self.tunnelProvider = tunnelProvider
        self.timerQueue = timerQueue
        self.log = log

        os_log("[+] %{public}@", log: .networkProtectionMemoryLog, type: .debug, String(describing: self))
    }

    deinit {
        os_log("[-] %{public}@", log: .networkProtectionMemoryLog, type: .debug, String(describing: self))

        cancelTimerImmediately()
    }

    // MARK: - Start/Stop monitoring

    func start() async throws {
        guard await !timerRunCoordinator.isRunning else {
            os_log("Will not start the tunnel failure monitor as it's already running", log: log)
            return
        }

        os_log("⚫️ Starting tunnel failure monitor", log: log)

        do {
            networkMonitor.start(queue: .global())

            failureReported = false
            try await scheduleTimer()
        } catch {
            os_log("⚫️ Stopping tunnel failure monitor prematurely", log: log)
            throw error
        }
    }

    func stop() async {
        os_log("⚫️ Stopping tunnel failure monitor", log: log)
        await stopScheduledTimer()

        networkMonitor.cancel()
    }

    // MARK: - Timer scheduling

    private func scheduleTimer() async throws {
        await stopScheduledTimer()

        await timerRunCoordinator.start()

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        self.timer = timer

        timer.schedule(deadline: .now() + Self.monitoringInterval, repeating: Self.monitoringInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }

            Task {
                try? await self.monitorHandshakes()
            }
        }

        timer.setCancelHandler { [weak self] in
            self?.timer = nil
        }

        timer.resume()
    }

    private func stopScheduledTimer() async {
        await timerRunCoordinator.stop()

        cancelTimerImmediately()
    }

    private func cancelTimerImmediately() {
        guard let timer else { return }

        if !timer.isCancelled {
            timer.cancel()
        }

        self.timer = nil
    }

    // MARK: - Handshake monitor

    @MainActor
    func monitorHandshakes() async throws {
        let mostRecentHandshake = await tunnelProvider.mostRecentHandshake() ?? 0

        let difference = Date().timeIntervalSince1970 - mostRecentHandshake
        os_log("⚫️ Last handshake: %{public}f seconds ago", log: .networkProtectionPixel, type: .debug, difference)

        if difference > Result.failureDetected.threshold, isConnected {
            if failureReported {
                os_log("⚫️ Tunnel failure already reported", log: .networkProtectionPixel, type: .debug)
            } else {
                failureSubject.send(.failureDetected)
                failureReported = true
            }
        } else if difference <= Result.failureDetected.threshold, failureReported {
            failureSubject.send(.failureRecovered)
            failureReported = false
        }
    }

    var isConnected: Bool {
        let path = networkMonitor.currentPath
        let connectionType = NetworkConnectionType(nwPath: path)

        return [.wifi, .eth, .cellular].contains(connectionType) && path.status == .satisfied
    }
}
