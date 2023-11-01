//
//  TabsProvider.swift
//  DuckDuckGo
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
import BrowserServicesKit
import Combine
import CoreData
import DDGSync
import Persistence

// swiftlint:disable:next type_body_length
public final class TabsProvider: DataProvider {

    public init(
        tabsStore: DeviceTabsStoring & CurrentDeviceTabsSource,
        metadataStore: SyncMetadataStore,
        syncDidUpdateData: @escaping () -> Void
    ) {
        self.tabsStore = tabsStore
        super.init(feature: .init(name: "tabs"), metadataStore: metadataStore, syncDidUpdateData: syncDidUpdateData)
    }

    // MARK: - DataProviding

    public override func prepareForFirstSync() throws {}

    public override func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        guard tabsStore.isCurrentDeviceTabsChanged else {
            return []
        }

        return [
            try Syncable(deviceTabsInfo: try await tabsStore.getCurrentDeviceTabs(), lastModified: Date(), encryptedUsing: crypter.encryptAndBase64Encode)
        ]
    }

    public override func handleInitialSyncResponse(
        received: [Syncable],
        clientTimestamp: Date,
        serverTimestamp: String?,
        crypter: Crypting
    ) async throws {
        try await handleSyncResponse(
            isInitial: true,
            sent: [],
            received: received,
            clientTimestamp: clientTimestamp,
            serverTimestamp: serverTimestamp,
            crypter: crypter
        )
    }

    public override func handleSyncResponse(
        sent: [Syncable],
        received: [Syncable],
        clientTimestamp: Date,
        serverTimestamp: String?,
        crypter: Crypting
    ) async throws {
        try await handleSyncResponse(
            isInitial: false,
            sent: sent,
            received: received,
            clientTimestamp: clientTimestamp,
            serverTimestamp: serverTimestamp,
            crypter: crypter
        )
    }

    // MARK: - Internal

    // swiftlint:disable:next function_body_length function_parameter_count
    func handleSyncResponse(
        isInitial: Bool,
        sent: [Syncable],
        received: [Syncable],
        clientTimestamp: Date,
        serverTimestamp: String?,
        crypter: Crypting
    ) async throws {

        var receivedByUUID = received.reduce(into: [String: SyncableTabsAdapter]()) { partialResult, syncable in
            let adapter = SyncableTabsAdapter(syncable: syncable)
            guard let uuid = adapter.uuid else {
                return
            }
            partialResult[uuid] = adapter
        }

        var devicesTabsInfo = try tabsStore.getDeviceTabs()
        for i in 0..<devicesTabsInfo.count {
            let uuid = devicesTabsInfo[i].deviceId

            if let receivedDeviceTabsInfo = receivedByUUID[uuid], let encryptedReceivedDeviceTabs = receivedDeviceTabsInfo.encryptedDeviceTabs {
                let receivedDeviceTabsJSONString = try crypter.base64DecodeAndDecrypt(encryptedReceivedDeviceTabs)
                if let receivedDeviceTabsData = receivedDeviceTabsJSONString.data(using: .utf8),
                   let receivedDeviceTabsJSON = try JSONSerialization.jsonObject(with: receivedDeviceTabsData) as? [[String:String]] {

                    let tabsInfo = try receivedDeviceTabsJSON.map { try TabInfo.init(json: $0) }
                    devicesTabsInfo[i] = .init(deviceId: uuid, deviceTabs: tabsInfo)
                    receivedByUUID.removeValue(forKey: uuid)
                }
            }
        }

        try receivedByUUID.forEach { uuid, syncable in
            if let encryptedReceivedDeviceTabs = syncable.encryptedDeviceTabs {
                let receivedDeviceTabsJSONString = try crypter.base64DecodeAndDecrypt(encryptedReceivedDeviceTabs)
                if let receivedDeviceTabsData = receivedDeviceTabsJSONString.data(using: .utf8),
                   let receivedDeviceTabsJSON = try JSONSerialization.jsonObject(with: receivedDeviceTabsData) as? [[String:String]] {

                    let tabsInfo = try receivedDeviceTabsJSON.map { try TabInfo.init(json: $0) }
                    devicesTabsInfo.append(.init(deviceId: uuid, deviceTabs: tabsInfo))
                }
            }
        }

        try tabsStore.storeDeviceTabs(devicesTabsInfo)

        if let serverTimestamp {
            lastSyncTimestamp = serverTimestamp
            syncDidUpdateData()
        }
    }

    private let tabsStore: DeviceTabsStoring & CurrentDeviceTabsSource
    private let errorSubject = PassthroughSubject<Error, Never>()

    // MARK: - Test Support

#if DEBUG
    var willSaveContextAfterApplyingSyncResponse: () throws -> Void = {}
#endif
}
