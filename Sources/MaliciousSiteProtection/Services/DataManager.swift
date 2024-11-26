//
//  DataManager.swift
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
import os

public protocol DataManaging {
    func dataSet<DataKey: MaliciousSiteDataKeyProtocol>(for key: DataKey) async -> DataKey.DataSetType
    func store<DataKey: MaliciousSiteDataKeyProtocol>(_ dataSet: DataKey.DataSetType, for key: DataKey) async
}

public actor DataManager: DataManaging {

    private let embeddedDataProvider: EmbeddedDataProviding
    private let fileStore: FileStoring

    public typealias FileNameProvider = (DataManager.StoredDataType) -> String
    private nonisolated let fileNameProvider: FileNameProvider

    private var store: [StoredDataType: Any] = [:]

    public init(fileStore: FileStoring, embeddedDataProvider: EmbeddedDataProviding, fileNameProvider: @escaping FileNameProvider) {
        self.embeddedDataProvider = embeddedDataProvider
        self.fileStore = fileStore
        self.fileNameProvider = fileNameProvider
    }

    public func dataSet<DataKey: MaliciousSiteDataKeyProtocol>(for key: DataKey) -> DataKey.DataSetType {
        let dataType = key.dataType
        // return cached dataSet if available
        if let data = store[key.dataType] as? DataKey.DataSetType {
            return data
        }

        // read stored dataSet if it‘s newer than the embedded one
        let dataSet = readStoredDataSet(for: key) ?? {
            // no stored dataSet or the embedded one is newer
            let embeddedRevision = embeddedDataProvider.revision(for: dataType)
            let embeddedItems = embeddedDataProvider.loadDataSet(for: key)
            return .init(revision: embeddedRevision, items: embeddedItems)
        }()

        // cache
        store[dataType] = dataSet

        return dataSet
    }

    private func readStoredDataSet<DataKey: MaliciousSiteDataKeyProtocol>(for key: DataKey) -> DataKey.DataSetType? {
        let dataType = key.dataType
        let fileName = fileNameProvider(dataType)
        guard let data = fileStore.read(from: fileName) else { return nil }

        let storedDataSet: DataKey.DataSetType
        do {
            storedDataSet = try JSONDecoder().decode(DataKey.DataSetType.self, from: data)
        } catch {
            Logger.dataManager.error("Error decoding \(fileName): \(error.localizedDescription)")
            return nil
        }

        // compare to the embedded data revision
        let embeddedDataRevision = embeddedDataProvider.revision(for: dataType)
        guard storedDataSet.revision >= embeddedDataRevision else {
            Logger.dataManager.error("Stored \(fileName) is outdated: revision: \(storedDataSet.revision), embedded revision: \(embeddedDataRevision).")
            return nil
        }

        return storedDataSet
    }

    public func store<DataKey: MaliciousSiteDataKeyProtocol>(_ dataSet: DataKey.DataSetType, for key: DataKey) {
        let dataType = key.dataType
        let fileName = fileNameProvider(dataType)
        self.store[dataType] = dataSet

        let data: Data
        do {
            data = try JSONEncoder().encode(dataSet)
        } catch {
            Logger.dataManager.error("Error encoding \(fileName): \(error.localizedDescription)")
            assertionFailure("Failed to store data to \(fileName): \(error)")
            return
        }

        let success = fileStore.write(data: data, to: fileName)
        assert(success)
    }

}
