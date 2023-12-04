//
//  NetworkProtectionLatencyReporter.swift
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

import Combine
import Foundation
import Common
import Network

protocol LatencyMeasurer: Sendable {
    func ping() async -> Result<Pinger.PingResult, Pinger.PingError>
}
extension Pinger: LatencyMeasurer {}

actor NetworkProtectionLatencyReporter {

    struct Configuration {
        let pingInterval: TimeInterval
        let timeout: TimeInterval

        init(pingInterval: TimeInterval = .seconds(20),
             timeout: TimeInterval = .seconds(5)) {

            self.pingInterval = pingInterval
            self.timeout = timeout
        }

        static let `default` = Configuration()
    }

    private let configuration: Configuration

    private nonisolated let getLogger: (@Sendable () -> OSLog)

    @MainActor
    private var task: Task<Never, Error>? {
        willSet {
            task?.cancel()
        }
    }

    @MainActor
    private(set) var currentIP: IPv4Address?
    @MainActor
    var isStarted: Bool {
        task?.isCancelled == false
    }

    typealias PingerFactory = @Sendable (IPv4Address, TimeInterval) -> LatencyMeasurer
    private let pingerFactory: PingerFactory

    init(configuration: Configuration = .default,
         log: @autoclosure @escaping (@Sendable () -> OSLog) = .disabled,
         pingerFactory: PingerFactory? = nil) {

        self.configuration = configuration
        self.getLogger = log
        self.pingerFactory = pingerFactory ?? { ip, timeout in
            Pinger(ip: ip, timeout: timeout, log: log())
        }
    }

    @MainActor
    func start(ip: IPv4Address, reportCallback: @escaping @Sendable (TimeInterval) -> Void) {
        let log = { @Sendable [weak self] in self?.getLogger() ?? .disabled }
        let pinger = pingerFactory(ip, configuration.timeout)
        self.currentIP = ip

        // run periodic latency measurement with initial delay and following interval
        task = Task.periodic(interval: configuration.pingInterval) {
            do {
                // ping the host
                let latency = try await pinger.ping().get().time

                // report
                reportCallback(latency)
            } catch {
                os_log("ping failed: %s", log: log(), type: .error, error.localizedDescription)
            }
        }
    }

    @MainActor
    func stop() {
        task = nil
    }

    deinit {
        task?.cancel()
    }

}
