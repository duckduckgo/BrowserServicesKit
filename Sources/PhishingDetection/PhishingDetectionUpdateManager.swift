//
//  PhishingDetectionUpdateManager.swift
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
import Common

public protocol PhishingDetectionUpdateManaging {
    func updateFilterSet() async
    func updateHashPrefixes() async
}

public class PhishingDetectionUpdateManager: PhishingDetectionUpdateManaging {
    var apiClient: PhishingDetectionClientProtocol
    var dataStore: PhishingDetectionDataSaving

    public init(client: PhishingDetectionClientProtocol, dataStore: PhishingDetectionDataSaving) {
        self.apiClient = client
        self.dataStore = dataStore
    }

    public func updateFilterSet() async {
        let response = await apiClient.getFilterSet(revision: dataStore.currentRevision)
        if response.replace {
            self.dataStore.saveFilterSet(set: Set(response.insert))
        } else {
            var newFilterSet = dataStore.filterSet
            response.insert.forEach { newFilterSet.insert($0) }
            response.delete.forEach { newFilterSet.remove($0) }
            self.dataStore.saveFilterSet(set: newFilterSet)
        }
        dataStore.saveRevision(response.revision)
        os_log(.debug, log: .phishingDetection, "\(self): 🟢 filterSet updated to revision \(dataStore.currentRevision)")
    }

    public func updateHashPrefixes() async {
        let response = await apiClient.getHashPrefixes(revision: dataStore.currentRevision)
        if response.replace {
            self.dataStore.saveHashPrefixes(set: Set(response.insert))
        } else {
            var newHashPrefixes = dataStore.hashPrefixes
            response.insert.forEach { newHashPrefixes.insert($0) }
            response.delete.forEach { newHashPrefixes.remove($0) }
            self.dataStore.saveHashPrefixes(set: newHashPrefixes)
        }
        dataStore.saveRevision(response.revision)
        os_log(.debug, log: .phishingDetection, "\(self): 🟢 hashPrefixes updated to revision \(dataStore.currentRevision)")
    }
}
