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

// Tried this but pain ensued
//protocol ActivitySchedulerProtocol {
//    var repeats: Bool { get set }
//    var interval: TimeInterval { get set }
//    var tolerance: TimeInterval { get set }
//    var qualityOfService: QualityOfService { get set }
//    func schedule(completion: @escaping @Sendable (@escaping NSBackgroundActivityScheduler.CompletionHandler) -> Void)
//}
//
//class MockActivityScheduler: ActivitySchedulerProtocol {
//    
//    var repeats: Bool = false
//    var interval: TimeInterval = 0
//    var tolerance: TimeInterval = 0
//    var qualityOfService: QualityOfService = .utility
//    var scheduleCalled = false
//    
//    func schedule(completion: @escaping @Sendable (@escaping NSBackgroundActivityScheduler.CompletionHandler) -> Void) {
//        scheduleCalled = true
//        DispatchQueue.main.async {
//            completion(NSBackgroundActivityScheduler.Result.finished)
//        }
//    }
//}
//
//extension NSBackgroundActivityScheduler: ActivitySchedulerProtocol {
//    func schedule(completion: @escaping @Sendable (@escaping NSBackgroundActivityScheduler.CompletionHandler) -> Void) {
//        self.schedule(completion: completion)
//    }
//}

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
        Task {
            self.hashPrefixDataActivity.start()
            self.filterSetDataActivity.start()
        }
    }
}

class HashPrefixDataActivity {
    private var activityScheduler: NSBackgroundActivityScheduler
    private let detectionService: PhishingDetectionServiceProtocol

    init(identifier: String, detectionService: PhishingDetectionServiceProtocol, interval: TimeInterval) {
        self.activityScheduler = NSBackgroundActivityScheduler(identifier: "com.duckduckgo.protection.hashprefixes")
        self.activityScheduler.repeats = true
        self.activityScheduler.interval = interval
        self.activityScheduler.tolerance = interval / 10
        self.activityScheduler.qualityOfService = .utility
        self.detectionService = detectionService
    }
    
    func start() {
        activityScheduler.schedule { (completion: @escaping NSBackgroundActivityScheduler.CompletionHandler) in
            Task.detached {
                await self.detectionService.updateHashPrefixes()
                completion(NSBackgroundActivityScheduler.Result.finished)
            }
        }
    }
}

class FilterSetDataActivity {
    private let activityScheduler: NSBackgroundActivityScheduler
    private let detectionService: PhishingDetectionServiceProtocol

    init(identifier: String, detectionService: PhishingDetectionServiceProtocol, interval: TimeInterval) {
        self.activityScheduler = NSBackgroundActivityScheduler(identifier: "com.duckduckgo.protection.filterset")
        self.activityScheduler.repeats = true
        self.activityScheduler.interval = interval
        self.activityScheduler.tolerance = interval / 10
        self.activityScheduler.qualityOfService = .utility
        self.detectionService = detectionService
    }
    
    func start() {
        let detectionService = self.detectionService
        activityScheduler.schedule { [weak self] (completion: @escaping NSBackgroundActivityScheduler.CompletionHandler) in
            guard self != nil else { return }
            Task.detached {
                await detectionService.updateFilterSet()
                completion(.finished)
            }
        }
    }
}
