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

public protocol PhishingDetectionUpdateManaging {
    func updateFilterSet() async
    func updateHashPrefixes() async
}

public class PhishingDetectionUpdateManager: PhishingDetectionUpdateManaging {
    var apiClient: PhishingDetectionClientProtocol
    var dataStore: PhishingDetectionDataStore
    
    public init(client: PhishingDetectionClientProtocol, dataStore: PhishingDetectionDataStore) {
        self.apiClient = client
        self.dataStore = dataStore
    }
    
    public func updateFilterSet() async {
        let response = await apiClient.getFilterSet(revision: dataStore.currentRevision)
        if response.replace {
            self.dataStore.filterSet = Set(response.insert)
        } else {
            response.insert.forEach { dataStore.filterSet.insert($0) }
            response.delete.forEach { dataStore.filterSet.remove($0) }
        }
        dataStore.currentRevision = response.revision
        dataStore.writeData()
    }

    public func updateHashPrefixes() async {
        let response = await apiClient.getHashPrefixes(revision: dataStore.currentRevision)
        if response.replace {
            dataStore.hashPrefixes = Set(response.insert)
        } else {
            response.insert.forEach { dataStore.hashPrefixes.insert($0) }
            response.delete.forEach { dataStore.hashPrefixes.remove($0) }
        }
        dataStore.currentRevision = response.revision
        dataStore.writeData()
    }
}
