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
    func updateData(for key: some MaliciousSiteDataKey) async

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

    public func updateData<DataKey: MaliciousSiteDataKey>(for key: DataKey) async {
        // load currently stored data set
        var dataSet = await dataManager.dataSet(for: key)
        let oldRevision = dataSet.revision

        // get change set from current revision from API
        let changeSet: APIClient.ChangeSetResponse<DataKey.DataSet.Element>
        do {
            let request = DataKey.DataSet.APIRequest(threatKind: key.threatKind, revision: oldRevision)
            changeSet = try await apiClient.load(request)
        } catch {
            Logger.updateManager.error("error fetching filter set: \(error)")
            return
        }
        guard !changeSet.isEmpty || changeSet.revision != dataSet.revision else {
            Logger.updateManager.debug("no changes to filter set")
            return
        }

        // apply changes
        dataSet.apply(changeSet)

        // store back
        await self.dataManager.store(dataSet, for: key)
        Logger.updateManager.debug("\(type(of: key)).\(key.threatKind) updated from rev.\(oldRevision) to rev.\(dataSet.revision)")
    }

    public func updateFilterSet() async {
        await updateData(for: .filterSet(threatKind: .phishing))
    }

    public func updateHashPrefixes() async {
        await updateData(for: .hashPrefixes(threatKind: .phishing))
    }

}
