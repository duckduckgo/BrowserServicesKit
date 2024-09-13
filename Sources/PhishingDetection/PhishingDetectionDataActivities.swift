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
import os

public protocol BackgroundActivityScheduling: Actor {
    func start()
    func stop()
}

actor BackgroundActivityScheduler: BackgroundActivityScheduling {

    private var task: Task<Void, Never>?
    private var timer: Timer?
    private let interval: TimeInterval
    private let identifier: String
    private let activity: () async -> Void

    init(interval: TimeInterval, identifier: String, activity: @escaping () async -> Void) {
        self.interval = interval
        self.identifier = identifier
        self.activity = activity
    }

    func start() {
        stop()
        task = Task {
            let taskId = UUID().uuidString
            while !Task.isCancelled {
                await activity()
                do {
                    Logger.phishingDetectionTasks.debug("🟢 \(self.identifier) task was executed in instance \(taskId)")
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    Logger.phishingDetectionTasks.error("🔴 Error \(self.identifier) task was cancelled before it could finish sleeping.")
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

public protocol PhishingDetectionDataActivityHandling {
    func start()
    func stop()
}

public class PhishingDetectionDataActivities: PhishingDetectionDataActivityHandling {
    private var schedulers: [BackgroundActivityScheduler]
    private var running: Bool = false

    var dataProvider: PhishingDetectionDataProviding

    public init(hashPrefixInterval: TimeInterval = 20 * 60, filterSetInterval: TimeInterval = 12 * 60 * 60, phishingDetectionDataProvider: PhishingDetectionDataProviding, updateManager: PhishingDetectionUpdateManaging) {
        let hashPrefixScheduler = BackgroundActivityScheduler(
            interval: hashPrefixInterval,
            identifier: "hashPrefixes.update",
            activity: { await updateManager.updateHashPrefixes() }
        )
        let filterSetScheduler = BackgroundActivityScheduler(
            interval: filterSetInterval,
            identifier: "filterSet.update",
            activity: { await updateManager.updateFilterSet() }
        )
        self.schedulers = [hashPrefixScheduler, filterSetScheduler]
        self.dataProvider = phishingDetectionDataProvider
    }

    public func start() {
        if !running {
            Task {
                for scheduler in schedulers {
                    await scheduler.start()
                }
            }
            running = true
        }
    }

    public func stop() {
        Task {
             for scheduler in schedulers {
                 await scheduler.stop()
             }
         }
         running = false
    }
}
