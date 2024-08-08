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
    private let interval: TimeInterval
    private let identifier: String

    init(interval: TimeInterval, identifier: String) {
        self.interval = interval
        self.identifier = identifier
    }

    func start(activity: @escaping () async -> Void) {
        stop()
        task = Task {
            let taskId = UUID().uuidString
            while true {
                await activity()
                do {
                    os_log(.debug, log: .phishingDetection, "\(self): 🟢 \(identifier) task was executed in instance \(taskId)")
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    os_log(.debug, log: .phishingDetection, "\(self): 🔴 Error \(identifier) task was cancelled before it could finish sleeping.")
                    break
                }
            }
        }
    }

    func stop() {
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
