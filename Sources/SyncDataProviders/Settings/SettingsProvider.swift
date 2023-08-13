//
//  SettingsProvider.swift
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
import DDGSync
import Persistence

public final class SettingsProvider: DataProvider {

    public enum Setting: String, CaseIterable {
        case duckAddress
    }

    public convenience init(
        metadataDatabase: CoreDataDatabase,
        metadataStore: SyncMetadataStore,
        emailManager: EmailManager,
        syncDidUpdateData: @escaping () -> Void
    ) {
        self.init(
            metadataDatabase: metadataDatabase,
            metadataStore: metadataStore,
            settingsAdapters: [.duckAddress: DuckAddressAdapter(emailManager: emailManager)],
            syncDidUpdateData: syncDidUpdateData
        )
    }

    public init(
        metadataDatabase: CoreDataDatabase,
        metadataStore: SyncMetadataStore,
        settingsAdapters: [Setting: any SettingsSyncAdapter],
        syncDidUpdateData: @escaping () -> Void
    ) {
        self.metadataDatabase = metadataDatabase
        self.settingsAdapters = settingsAdapters
        super.init(feature: .init(name: "settings"), metadataStore: metadataStore, syncDidUpdateData: syncDidUpdateData)
    }

    // MARK: - DataProviding

    public override func prepareForFirstSync() throws {
        var saveError: Error?

        let keys = settingsAdapters.keys.map(\.rawValue)
        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let currentTimestamp = Date()

        context.performAndWait {
            do {
                let allMetadataObjectsRequest = SyncableSettingsMetadata.fetchRequest()
                let allMetadataObjects = try context.fetch(allMetadataObjectsRequest)
                for metadataObject in allMetadataObjects {
                    context.delete(metadataObject)
                }

                for key in settingsAdapters.keys.map(\.rawValue) {
                    let metadataObject = SyncableSettingsMetadata(context: context)
                    metadataObject.key = key
                    metadataObject.lastModified = currentTimestamp
                }
                try context.save()

            } catch {
                saveError = error
            }
        }

        if let saveError {
            throw saveError
        }
    }

    public override func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        var syncableSettings = [Syncable]()
        var fetchError: Error?

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let encryptionKey = try crypter.fetchSecretKey()

        context.performAndWait {
            do {
                let modifiedSettings = try SyncableSettingsMetadataUtils.fetchMetadataForSettingsPendingSync(in: context)
                for modifiedSetting in modifiedSettings {
                    guard let setting = Setting(rawValue: modifiedSetting.key), let adapter = settingsAdapters[setting] else {
                        // todo: error
                        continue
                    }
                    let value = try adapter.getValue()
                    syncableSettings.append(
                        try Syncable(
                            setting: setting,
                            value: value,
                            lastModified: modifiedSetting.lastModified,
                            encryptedUsing: { try crypter.encryptAndBase64Encode($0, using: encryptionKey) }
                        )
                    )
                }
            } catch {
                fetchError = error
            }
        }

        if let fetchError {
            throw fetchError
        }

        return syncableSettings
    }

    public override func handleInitialSyncResponse(received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        try await handleSyncResponse(isInitial: true, sent: [], received: received, clientTimestamp: clientTimestamp, serverTimestamp: serverTimestamp, crypter: crypter)
    }

    public override func handleSyncResponse(sent: [Syncable], received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        try await handleSyncResponse(isInitial: false, sent: sent, received: received, clientTimestamp: clientTimestamp, serverTimestamp: serverTimestamp, crypter: crypter)
    }

    // MARK: - Internal

    func handleSyncResponse(isInitial: Bool, sent: [Syncable], received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
    }

    func cleanUpSentItems(_ sent: [Syncable], receivedUUIDs: Set<String>, clientTimestamp: Date) throws -> Set<String> {
        []
    }

    private func clearModifiedAt(uuids: Set<String>, clientTimestamp: Date) throws {
    }

    // MARK: - Private
    private let metadataDatabase: CoreDataDatabase
    private let settingsAdapters: [Setting: any SettingsSyncAdapter]

    enum Const {
        static let maxContextSaveRetries = 5
    }

}
