//
//  PhishingDetectionDataActivities.swift
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

public protocol BackgroundActivityScheduling {
    func start(activity: @escaping () async -> Void)
    func stop()
}

actor final class BackgroundActivityScheduler: BackgroundActivityScheduling {
    private var task: Task<Void, Never>?
    private var timer: Timer?
    private let interval: TimeInterval
    private let identifier: String

    init(interval: TimeInterval, identifier: String) {
        self.interval = interval
        self.identifier = identifier
    }

    func start(activity: @escaping () async throws -> Void) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.task = Task {
                let taskId = UUID().uuidString
                do {
                    try await activity()
                    os_log(.debug, log: .phishingDetection, "\(self): 🟢 \(self.identifier) task was executed in instance \(taskId)")
                } catch {
                    os_log(.error, log: .phishingDetection, "\(self): 🔴 \(self.identifier) task failed in instance \(taskId) with error: \(error)")
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
    }
}

public protocol PhishingDetectionDataActivityHandling {
    func start()
    func stop()
}

public class PhishingDetectionDataActivities: PhishingDetectionDataActivityHandling {
    private var schedulers: [BackgroundActivityScheduler]
    private var running: Bool = false

    var dataProvider: PhishingDetectionDataProviding

    public init(detectionService: PhishingDetecting, hashPrefixInterval: TimeInterval = 20 * 60, filterSetInterval: TimeInterval = 12 * 60 * 60, phishingDetectionDataProvider: PhishingDetectionDataProviding, updateManager: PhishingDetectionUpdateManaging) {
        let hashPrefixScheduler = BackgroundActivityScheduler(
            interval: hashPrefixInterval,
            identifier: "hashPrefixes.update"
        )
        let filterSetScheduler = BackgroundActivityScheduler(
            interval: filterSetInterval,
            identifier: "filterSet.update"
        )
        self.schedulers = [hashPrefixScheduler, filterSetScheduler]
        self.dataProvider = phishingDetectionDataProvider

        // Start the schedulers
        hashPrefixScheduler.start(activity: { await updateManager.updateHashPrefixes() })
        filterSetScheduler.start(activity: { await updateManager.updateFilterSet() })
    }

    public func start() {
        if !running {
            schedulers.forEach { $0.start() }
        }
        running = true
    }

    public func stop() {
        if running {
            schedulers.forEach { $0.stop() }
        }
        running = false
    }
}
