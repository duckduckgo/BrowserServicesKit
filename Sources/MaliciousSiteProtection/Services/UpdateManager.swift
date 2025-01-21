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

import Common
import Foundation
import Networking
import os
import PixelKit

public protocol MaliciousSiteUpdateManaging {
    var lastHashPrefixSetUpdateDate: Date { get }
    var lastFilterSetUpdateDate: Date { get }

    func startPeriodicUpdates() -> Task<Void, Error>
    func updateData(datasetType: DataManager.StoredDataType.Kind) -> Task<Void, any Error>
}

protocol InternalUpdateManaging: MaliciousSiteUpdateManaging {
    @discardableResult
    func updateData(for key: some MaliciousSiteDataKey) async -> Bool
}

public struct UpdateManager: InternalUpdateManaging {

    private let apiClient: APIClient.Mockable
    private let dataManager: DataManaging

    public typealias UpdateIntervalProvider = (DataManager.StoredDataType) -> TimeInterval?
    private let updateIntervalProvider: UpdateIntervalProvider
    private let sleeper: Sleeper
    private let updateInfoStorage: MaliciousSiteProtectioUpdateManagerInfoStorage

    public var lastHashPrefixSetUpdateDate: Date {
        updateInfoStorage.lastHashPrefixSetsUpdateDate
    }

    public var lastFilterSetUpdateDate: Date {
        updateInfoStorage.lastFilterSetsUpdateDate
    }

    public init(apiEnvironment: APIClientEnvironment, service: APIService = DefaultAPIService(urlSession: .shared), dataManager: DataManager, updateIntervalProvider: @escaping UpdateIntervalProvider) {
        self.init(apiClient: APIClient(environment: apiEnvironment, service: service), dataManager: dataManager, updateIntervalProvider: updateIntervalProvider)
    }

    init(apiClient: APIClient.Mockable, dataManager: DataManaging, sleeper: Sleeper = .default, updateInfoStorage: MaliciousSiteProtectioUpdateManagerInfoStorage = MaliciousSiteProtectionUpdateManagerInfoStore(),  updateIntervalProvider: @escaping UpdateIntervalProvider) {
        self.apiClient = apiClient
        self.dataManager = dataManager
        self.updateIntervalProvider = updateIntervalProvider
        self.sleeper = sleeper
        self.updateInfoStorage = updateInfoStorage
    }

    @discardableResult
    func updateData<DataKey: MaliciousSiteDataKey>(for key: DataKey) async -> Bool {
        // load currently stored data set
        var dataSet = await dataManager.dataSet(for: key)
        let oldRevision = dataSet.revision

        // get change set from current revision from API
        let changeSet: APIClient.ChangeSetResponse<DataKey.DataSet.Element>
        do {
            let request = DataKey.DataSet.APIRequest(threatKind: key.threatKind, revision: oldRevision)
            changeSet = try await apiClient.load(request)
        } catch APIRequestV2.Error.urlSession(let error as URLError) {
            Logger.updateManager.error("error fetching \(type(of: key)).\(key.threatKind): \(error)")
            fireNetworkIssuePixelIfNeeded(error: error, threatKind: key.threatKind, datasetType: key.dataType.kind)
            return false
        }
        catch {
            Logger.updateManager.error("error fetching \(type(of: key)).\(key.threatKind): \(error)")
            return false
        }
        guard !changeSet.isEmpty || changeSet.revision != dataSet.revision else {
            Logger.updateManager.debug("no changes to \(type(of: key)).\(key.threatKind)")
            // If change set is empty or revision is the same we consider a successfull update in terms of last refresh date.
            return true
        }

        // apply changes
        dataSet.apply(changeSet)

        // store back
        guard await self.dataManager.store(dataSet, for: key) else {
            Logger.updateManager.error("\(type(of: key)).\(key.threatKind) failed to be saved")
            return false
        }
        Logger.updateManager.debug("\(type(of: key)).\(key.threatKind) updated from rev.\(oldRevision) to rev.\(dataSet.revision)")

        return true
    }

    public func startPeriodicUpdates() -> Task<Void, any Error> {
        Task.detached {
            // run update jobs in background for every data type
            try await withThrowingTaskGroup(of: Never.self) { group in
                for dataType in DataManager.StoredDataType.allCases {
                    // get update interval from provider
                    guard let updateInterval = updateIntervalProvider(dataType) else { continue }
                    guard updateInterval > 0 else {
                        assertionFailure("Update interval for \(dataType) must be positive")
                        continue
                    }

                    group.addTask {
                        // run periodically until the parent task is cancelled
                        try await performPeriodicJob(interval: updateInterval, sleeper: sleeper) {
                            await self.updateData(for: dataType.dataKey)
                        }
                    }
                }
                for try await _ in group {}
            }
        }
    }

    public func updateData(datasetType: DataManager.StoredDataType.Kind) -> Task<Void, any Error> {
        Task {
            // run update jobs in background for every data type
            await withTaskGroup(of: Bool.self) { group in
                for dataType in DataManager.StoredDataType.dataType(forKind: datasetType) {
                    group.addTask {
                        await self.updateData(for: dataType.dataKey)
                    }
                }

                // Check that at least one of the dataset type have updated
                let success = await group.reduce(false) { partial, newValue in
                    partial || newValue
                }

                if success {
                    await saveLastUpdateDate(for: datasetType)
                }
            }
        }
    }

    private func saveLastUpdateDate(for kind: DataManager.StoredDataType.Kind) async {
        await MainActor.run {
            let date = Date()
            switch kind {
            case .hashPrefixSet:
                updateInfoStorage.lastHashPrefixSetsUpdateDate = date
            case .filterSet:
                updateInfoStorage.lastFilterSetsUpdateDate = date
            }
        }
    }

    private func fireNetworkIssuePixelIfNeeded(error: URLError, threatKind: ThreatKind, datasetType: DataManager.StoredDataType.Kind) {
        switch error.code {
        case .notConnectedToInternet:
            PixelKit.fire(DebugEvent(Event.failedToDownloadInitialDataSets(category: threatKind, type: datasetType)))
        case .timedOut:
            // TODO: Send Pixel for timeout
            break
        default:
            break
        }
    }

}
