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

public protocol PhishingDetectionDataManaging {
    func loadDataAsync()
}

public class PhishingDetectionDataManager: PhishingDetectionDataManaging {
    private var phishingDetectionDataActivities: PhishingDetectionDataActivities
    private var dataStore: PhishingDetectionDataStore
    private var updateManager: PhishingDetectionUpdateManager

    public init(dataActivities: PhishingDetectionDataActivities, dataStore: PhishingDetectionDataStore, updateManager: PhishingDetectionUpdateManager) {
        self.phishingDetectionDataActivities = dataActivities
        self.updateManager = updateManager
        self.dataStore = dataStore
    }
    
    public func startDataActivities() {
        phishingDetectionDataActivities.start()
    }

    public func loadDataAsync() {
        Task {
            await dataStore.loadData()
            await updateManager.updateFilterSet()
            await updateManager.updateHashPrefixes()
        }
    }
}
