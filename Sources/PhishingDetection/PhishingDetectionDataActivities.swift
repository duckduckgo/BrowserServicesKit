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

final class BackgroundActivityScheduler: BackgroundActivityScheduling {
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

final class DataActivity {
    private let scheduler: BackgroundActivityScheduling
    private let updateAction: () async -> Void

    init(scheduler: BackgroundActivityScheduling, updateAction: @escaping () async -> Void) {
        self.scheduler = scheduler
        self.updateAction = updateAction
    }

    func start() {
        scheduler.start(activity: updateAction)
    }

    func stop() {
        scheduler.stop()
    }
}

public protocol PhishingDetectionDataActivityHandling {
    func start()
    func stop()
}

public class PhishingDetectionDataActivities: PhishingDetectionDataActivityHandling {
    private var activities: [DataActivity]
    private var running: Bool = false

    var dataProvider: PhishingDetectionDataProviding

    public init(detectionService: PhishingDetecting, hashPrefixInterval: TimeInterval = 20 * 60, filterSetInterval: TimeInterval = 12 * 60 * 60, phishingDetectionDataProvider: PhishingDetectionDataProviding, updateManager: PhishingDetectionUpdateManaging) {
        let hashPrefixActivity = DataActivity(
            scheduler: BackgroundActivityScheduler(interval: hashPrefixInterval, identifier: "hashPrefixes.update"),
            updateAction: { await updateManager.updateHashPrefixes() }
        )
        let filterSetActivity = DataActivity(
            scheduler: BackgroundActivityScheduler(interval: filterSetInterval, identifier: "filterSet.update"),
            updateAction: { await updateManager.updateFilterSet() }
        )
        self.activities = [hashPrefixActivity, filterSetActivity]
        self.dataProvider = phishingDetectionDataProvider
    }

    public func start() {
        if !running {
            activities.forEach { $0.start() }
        }
        running = true
    }

    public func stop() {
        if running {
            activities.forEach { $0.stop() }
        }
        running = false
    }
}
