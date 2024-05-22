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

public class PhishingDetectionDataActivities {
    private let hashPrefixDataActivity: HashPrefixDataActivity
    private let filterSetDataActivity: FilterSetDataActivity
    private let detectionService: PhishingDetectionServiceProtocol
    
    public init(detectionService: PhishingDetectionServiceProtocol? = nil) {
        let givenDetectionService = detectionService ?? PhishingDetectionService()
        self.detectionService = givenDetectionService
        self.hashPrefixDataActivity = HashPrefixDataActivity(identifier: "com.duckduckgo.protection.hashPrefix", detectionService: givenDetectionService)
        self.filterSetDataActivity = FilterSetDataActivity(identifier: "com.duckduckgo.protection.filterSet", detectionService: givenDetectionService)
    }
    
    public func run() async {
        await self.hashPrefixDataActivity.start()
        await self.filterSetDataActivity.start()
    }
}

class HashPrefixDataActivity {
    private let activityScheduler: NSBackgroundActivityScheduler
    private let detectionService: PhishingDetectionServiceProtocol

    init(identifier: String, detectionService: PhishingDetectionServiceProtocol) {
        activityScheduler = NSBackgroundActivityScheduler(identifier: identifier)
        activityScheduler.repeats = true
        activityScheduler.interval = 20 * 60 // Run every 20 minutes
        self.detectionService = detectionService
    }
    
    func start() async {
        activityScheduler.schedule { (completion: NSBackgroundActivityScheduler.CompletionHandler) in
            Task {
                await self.detectionService.updateHashPrefixes()
            }
            completion(.finished)
        }
    }
}

class FilterSetDataActivity {
    private let activityScheduler: NSBackgroundActivityScheduler
    private let detectionService: PhishingDetectionServiceProtocol

    init(identifier: String, detectionService: PhishingDetectionServiceProtocol) {
        activityScheduler = NSBackgroundActivityScheduler(identifier: identifier)
        activityScheduler.repeats = true
        activityScheduler.interval = 12 * 60 * 60 // Run every 12 hours
        self.detectionService = detectionService
    }
    
    func start() async {
        activityScheduler.schedule { (completion: NSBackgroundActivityScheduler.CompletionHandler) in
            Task {
                await self.detectionService.updateFilterSet()
            }
            completion(.finished)

        }
    }
}


