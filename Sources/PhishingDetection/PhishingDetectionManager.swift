//
//  PhishingDetectionManager.swift
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

public protocol PhishingDetectionManaging {
    func isMalicious(url: URL) async -> Bool
    func loadDataAsync()
    func isCachedMalicious(url: URL) async -> Bool
}

public final class PhishingDetectionManager: PhishingDetectionManaging {
    public static let shared = PhishingDetectionManager()

    private let phishingDetectionService = PhishingDetectionService()
    private let phishingDetectionDataActivities = PhishingDetectionDataActivities()
    private var cache: CacheSet<URL>

    private init() {
        cache = CacheSet<URL>(capacity: 50)
        loadDataAsync()
    }

    public func isMalicious(url: URL) async -> Bool {
        let malicious = await phishingDetectionService.isMalicious(url: url)
        if malicious {
            cache.insert(url)
        }
        return malicious
    }

    public func loadDataAsync() {
        Task {
            phishingDetectionService.loadData()
            await phishingDetectionDataActivities.run()
        }
    }
    
    public func isCachedMalicious(url: URL) async -> Bool {
        return cache.contains(url)
    }

}
