//
//  PhishingDataActivity.swift
//
//
//  Created by Thom on 03/05/2024.
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
        givenDetectionService.loadData()
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
            let semaphore = DispatchSemaphore(value: 0)

            Task {
                await self.detectionService.updateHashPrefixes()
                semaphore.signal()
            }

            semaphore.wait()
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
            let semaphore = DispatchSemaphore(value: 0)

            Task {
                await self.detectionService.updateFilterSet()
                semaphore.signal()
            }

            semaphore.wait()
        }
    }
}


