//
//  UpdateManager.swift
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
import os

public protocol UpdateManaging {
    func updateFilterSet() async
    func updateHashPrefixes() async
}

public struct UpdateManager: UpdateManaging {
    private let apiClient: APIClientProtocol
    private let dataManager: DataManaging

    public init(apiClient: APIClientProtocol, dataManager: DataManaging) {
        self.apiClient = apiClient
        self.dataManager = dataManager
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
        let response = await apiClient.getFilterSet(revision: dataManager.currentRevision)
        updateSet(
            currentSet: dataManager.filterSet,
            insert: response.insert,
            delete: response.delete,
            replace: response.replace
        ) { newSet in
            self.dataManager.saveFilterSet(set: newSet)
        }
        dataManager.saveRevision(response.revision)
        Logger.updateManager.debug("filterSet updated to revision \(self.dataManager.currentRevision)")
    }

    public func updateHashPrefixes() async {
        let response = await apiClient.getHashPrefixes(revision: dataManager.currentRevision)
        updateSet(
            currentSet: dataManager.hashPrefixes,
            insert: response.insert,
            delete: response.delete,
            replace: response.replace
        ) { newSet in
            self.dataManager.saveHashPrefixes(set: newSet)
        }
        dataManager.saveRevision(response.revision)
        Logger.updateManager.debug("hashPrefixes updated to revision \(self.dataManager.currentRevision)")
    }
}
