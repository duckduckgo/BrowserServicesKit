//
//  NetworkProtectionLatencyMonitor.swift
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
import Common
import Combine

final public class NetworkProtectionLatencyMonitor {
    public enum ConnectionQuality: String {
        case terrible
        case poor
        case moderate
        case good
        case excellent
        case unknown

        init(average: TimeInterval) {
            switch average {
            case 300...:
                self = .terrible
            case 200..<300:
                self = .poor
            case 50..<200:
                self = .moderate
            case 20..<50:
                self = .good
            case 0..<20:
                self = .excellent
            default:
                self = .unknown
            }
        }
    }

    public enum Result {
        case error
        case quality(ConnectionQuality)
    }

    private static let reportThreshold: TimeInterval = .minutes(10)
    private static let measurementInterval: TimeInterval = .seconds(5)
    private static let pingTimeout: TimeInterval = 0.3

    private static let unknownLatency: TimeInterval = -1

    public var publisher: AnyPublisher<Result, Never> {
        subject.eraseToAnyPublisher()
    }
    private let subject = PassthroughSubject<Result, Never>()

    private let latencySubject = PassthroughSubject<TimeInterval, Never>()
    private var latencyCancellable: AnyCancellable?

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

    private let lock = NSLock()

    private var _lastLatencyReported: Date = .distantPast
    private(set) var lastLatencyReported: Date {
        get {
            lock.lock(); defer { lock.unlock() }
            return _lastLatencyReported
        }
        set {
            lock.lock()
            self._lastLatencyReported = newValue
            lock.unlock()
        }
    }

    private let serverIP: () -> IPv4Address?

    private let log: OSLog

    private var _ignoreThreshold = false
    private(set) var ignoreThreshold: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _ignoreThreshold
        }
        set {
            lock.lock()
            self._ignoreThreshold = newValue
            lock.unlock()
        }
    }

    // MARK: - Init & deinit

    init(serverIP: @escaping () -> IPv4Address?, timerQueue: DispatchQueue, log: OSLog) {
        self.serverIP = serverIP
        self.timerQueue = timerQueue
        self.log = log

        os_log("[+] %{public}@", log: .networkProtectionMemoryLog, type: .debug, String(describing: self))
    }

    deinit {
        os_log("[-] %{public}@", log: .networkProtectionMemoryLog, type: .debug, String(describing: self))

        cancelTimerImmediately()
    }

    // MARK: - Start/Stop monitoring

    public func start() async throws {
        guard await !timerRunCoordinator.isRunning else {
            os_log("Will not start the latency monitor as it's already running", log: log)
            return
        }

        os_log("⚫️ Starting latency monitor", log: log)

        latencyCancellable = latencySubject.eraseToAnyPublisher()
            .scan(ExponentialGeometricAverage()) { [weak self] measurements, latency in
                if latency >= 0 {
                    measurements.addMeasurement(latency)
                    os_log("⚫️ Latency: %{public}f milliseconds", log: .networkProtectionPixel, type: .debug, latency)
                } else {
                    self?.subject.send(.error)
                }

                os_log("⚫️ Average: %{public}f milliseconds", log: .networkProtectionPixel, type: .debug, measurements.average)

                return measurements
            }
            .map { ConnectionQuality(average: $0.average) }
            .sink { [weak self] quality in
                let now = Date()
                if let self,
                    (now.timeIntervalSince1970 - self.lastLatencyReported.timeIntervalSince1970 >= Self.reportThreshold) || ignoreThreshold {
                    self.subject.send(.quality(quality))
                    self.lastLatencyReported = now
                }
            }

        do {
            try await scheduleTimer()
        } catch {
            os_log("⚫️ Stopping latency monitor prematurely", log: log)
            throw error
        }
    }

    public func stop() async {
        os_log("⚫️ Stopping latency monitor", log: log)
        await stopScheduledTimer()
    }

    // MARK: - Timer scheduling

    private func scheduleTimer() async throws {
        await stopScheduledTimer()

        await timerRunCoordinator.start()

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        self.timer = timer

        timer.schedule(deadline: .now() + Self.measurementInterval, repeating: Self.measurementInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }

            Task {
                await self.measureLatency()
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

    // MARK: - Latency monitor

    @MainActor
    public func measureLatency() async {
        guard let serverIP = serverIP() else {
            latencySubject.send(Self.unknownLatency)
            return
        }

        os_log("⚫️ Pinging %{public}s", log: .networkProtectionPixel, type: .debug, serverIP.debugDescription)

        let result = await Pinger(ip: serverIP, timeout: Self.pingTimeout, log: .networkProtectionPixel).ping()

        switch result {
        case .success(let pingResult):
            latencySubject.send(pingResult.time * 1000)
        case .failure(let error):
            os_log("⚫️ Ping error: %{public}s", log: .networkProtectionPixel, type: .debug, error.localizedDescription)
            latencySubject.send(Self.unknownLatency)
        }
    }

    public func simulateLatency(_ timeInterval: TimeInterval) {
        ignoreThreshold = true
        latencySubject.send(timeInterval)
        ignoreThreshold = false
    }
}

public final class ExponentialGeometricAverage {
    private static let decayConstant = 0.1
    private let cutover = ceil(1 / decayConstant)

    private var count = TimeInterval(0)
    private var value = TimeInterval(-1)

    public var average: TimeInterval {
        value
    }

    public func addMeasurement(_ measurement: TimeInterval) {
        let keepConstant = 1 - Self.decayConstant

        if count > cutover {
            value = exp(keepConstant * log(value) + Self.decayConstant * log(measurement))
        } else if count > 0 {
            let retained: Double = keepConstant * count / (count + 1.0)
            let newcomer = 1.0 - retained
            value = exp(retained * log(value) + newcomer * log(measurement))
        } else {
            value = measurement
        }
        count += 1
    }

    public func reset() {
        value = -1.0
        count = 0
    }
}
