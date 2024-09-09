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
import os

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

    private func updateSet<T: Hashable>(
        currentSet: Set<T>,
        insert: [T],
        delete: [T],
        replace: Bool,
        saveSet: (Set<T>) -> Void
    ) {
        var newSet = currentSet

        if replace {
            newSet = Set(insert)
        } else {
            newSet.formUnion(insert)
            newSet.subtract(delete)
        }

        saveSet(newSet)
    }

    public func updateFilterSet() async {
        let response = await apiClient.getFilterSet(revision: dataStore.currentRevision)
        updateSet(
            currentSet: dataStore.filterSet,
            insert: response.insert,
            delete: response.delete,
            replace: response.replace
        ) { newSet in
            self.dataStore.saveFilterSet(set: newSet)
        }
        dataStore.saveRevision(response.revision)
        Logger.phishingDetectionUpdateManager.debug("filterSet updated to revision \(self.dataStore.currentRevision)")
    }

    public func updateHashPrefixes() async {
        let response = await apiClient.getHashPrefixes(revision: dataStore.currentRevision)
        updateSet(
            currentSet: dataStore.hashPrefixes,
            insert: response.insert,
            delete: response.delete,
            replace: response.replace
        ) { newSet in
            self.dataStore.saveHashPrefixes(set: newSet)
        }
        dataStore.saveRevision(response.revision)
        Logger.phishingDetectionUpdateManager.debug("hashPrefixes updated to revision \(self.dataStore.currentRevision)")
    }
}
