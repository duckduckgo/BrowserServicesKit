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

// live in the client
public class PhishingStateManager {
    public var tabIsPhishing: Bool = false

    public init(){}

    public func setIsPhishing(_ isPhishing: Bool) {
        tabIsPhishing = isPhishing
    }
}

public protocol PhishingDetectionManaging {
    func isMalicious(url: URL) async -> Bool
    func loadDataAsync()
}

public class PhishingDetectionManager: PhishingDetectionManaging {
    private var phishingDetectionService: PhishingDetectionService
    private var phishingDetectionDataActivities: PhishingDetectionDataActivities

    public init(service: PhishingDetectionService, dataActivities: PhishingDetectionDataActivities) {
        self.phishingDetectionService = service
        self.phishingDetectionDataActivities = dataActivities
        loadDataAsync() // should be called from app or not?
    }

    public func isMalicious(url: URL) async -> Bool {
        let malicious = await phishingDetectionService.isMalicious(url: url)
        return malicious
    }

    public func loadDataAsync() {
        Task {
            await phishingDetectionService.loadData()
            await phishingDetectionDataActivities.run()
        }
    }
}
