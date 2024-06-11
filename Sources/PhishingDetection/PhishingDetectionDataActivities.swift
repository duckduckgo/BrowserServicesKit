//
//  PhishingDetectionDataActivities.swift
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

public protocol BackgroundActivityScheduling {
    func start(activity: @escaping () -> Void)
    func stop()
}

class BackgroundActivityScheduler: BackgroundActivityScheduling {
    private var timer: Timer?
    private let interval: TimeInterval
    let identifier: String

    init(identifier: String, interval: TimeInterval) {
        self.identifier = identifier
        self.interval = interval
    }

    func start(activity: @escaping () -> Void) {
        stop()
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: self.interval, repeats: true) { _ in
                DispatchQueue.global().async {
                    activity()
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

public class PhishingDetectionDataActivities {
    private let hashPrefixDataActivity: HashPrefixDataActivity
    private let filterSetDataActivity: FilterSetDataActivity
    private let detectionService: PhishingDetectionServiceProtocol

    public init(detectionService: PhishingDetectionServiceProtocol? = nil, hashPrefixInterval: TimeInterval = 20 * 60, filterSetInterval: TimeInterval = 12 * 60 * 60) {
        let givenDetectionService = detectionService ?? PhishingDetectionService()
        self.detectionService = givenDetectionService
        self.hashPrefixDataActivity = HashPrefixDataActivity(identifier: "com.duckduckgo.protection.hashPrefix", detectionService: givenDetectionService, interval: hashPrefixInterval)
        self.filterSetDataActivity = FilterSetDataActivity(identifier: "com.duckduckgo.protection.filterSet", detectionService: givenDetectionService, interval: filterSetInterval)
    }

    public func run() async {
        self.hashPrefixDataActivity.start()
        self.filterSetDataActivity.start()
    }
}

class HashPrefixDataActivity {
    private let activityScheduler: BackgroundActivityScheduling
    private let detectionService: PhishingDetectionServiceProtocol
    private let identifier: String
    private let interval: TimeInterval

    init(identifier: String, detectionService: PhishingDetectionServiceProtocol, interval: TimeInterval, scheduler: BackgroundActivityScheduling? = nil) {
        self.detectionService = detectionService
        self.identifier = identifier
        self.interval = interval
        self.activityScheduler = scheduler ?? BackgroundActivityScheduler(identifier: identifier, interval: interval)
    }

    func start() {
        activityScheduler.start { [weak self] in
            guard let self = self else { return }
            Task {
                await self.detectionService.updateHashPrefixes()
            }
        }
    }

    func stop() {
        activityScheduler.stop()
    }
}

class FilterSetDataActivity {
    private let activityScheduler: BackgroundActivityScheduling
    private let detectionService: PhishingDetectionServiceProtocol
    private let identifier: String
    private let interval: TimeInterval

    init(identifier: String, detectionService: PhishingDetectionServiceProtocol, interval: TimeInterval, scheduler: BackgroundActivityScheduling? = nil) {
        self.detectionService = detectionService
        self.identifier = identifier
        self.interval = interval
        self.activityScheduler = scheduler ?? BackgroundActivityScheduler(identifier: identifier, interval: interval)
    }
    
    func start() {
        activityScheduler.start { [weak self] in
            guard let self = self else { return }
            Task {
                await self.detectionService.updateFilterSet()
            }
        }
    }
    
    func stop() {
        activityScheduler.stop()
    }
}
