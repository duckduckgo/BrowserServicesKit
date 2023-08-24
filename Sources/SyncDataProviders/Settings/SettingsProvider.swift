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
import CoreData
import DDGSync
import Persistence

public final class SettingsProvider: DataProvider {

    public struct Setting: Hashable {
        let key: String

        init(key: String) {
            self.key = key
        }
    }

    public convenience init(
        metadataDatabase: CoreDataDatabase,
        metadataStore: SyncMetadataStore,
        emailManager: EmailManagerSyncSupporting,
        syncDidUpdateData: @escaping () -> Void
    ) {
        self.init(
            metadataDatabase: metadataDatabase,
            metadataStore: metadataStore,
            settingsHandlers: [.emailProtectionGeneration: EmailProtectionSyncHandler(emailManager: emailManager, metadataDatabase: metadataDatabase)],
            syncDidUpdateData: syncDidUpdateData
        )
    }

    public init(
        metadataDatabase: CoreDataDatabase,
        metadataStore: SyncMetadataStore,
        settingsHandlers: [Setting: any SettingsSyncHandling],
        syncDidUpdateData: @escaping () -> Void
    ) {
        self.metadataDatabase = metadataDatabase
        self.settingsHandlers = settingsHandlers
        super.init(feature: .init(name: "settings"), metadataStore: metadataStore, syncDidUpdateData: syncDidUpdateData)
    }

    // MARK: - DataProviding

    public override func prepareForFirstSync() throws {
        var saveError: Error?

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let currentTimestamp = Date()

        context.performAndWait {
            do {
                let allMetadataObjectsRequest = SyncableSettingsMetadata.fetchRequest()
                let allMetadataObjects = try context.fetch(allMetadataObjectsRequest)
                for metadataObject in allMetadataObjects {
                    context.delete(metadataObject)
                }

                for key in settingsHandlers.keys.map(\.key) {
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
                    let setting = Setting(key: modifiedSetting.key)
                    guard let settingHandler = settingsHandlers[setting] else {
                        // setting metadata object is not supported by the provider
                        continue
                    }
                    let value = try settingHandler.getValue()
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
        var saveError: Error?

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        var saveAttemptsLeft = Const.maxContextSaveRetries

        context.performAndWait {
            while true {

                do {
                    let responseHandler = try SettingsResponseHandler(
                        received: received,
                        clientTimestamp: clientTimestamp,
                        settingsHandlers: settingsHandlers,
                        context: context,
                        crypter: crypter,
                        deduplicateEntities: isInitial
                    )
                    let idsOfItemsToClearModifiedAt = try cleanUpSentItems(sent, receivedKeys: Set(responseHandler.receivedByKey.keys), clientTimestamp: clientTimestamp, in: context)
                    try responseHandler.processReceivedSettings()

#if DEBUG
                    try willSaveContextAfterApplyingSyncResponse()
#endif
                    let keys = idsOfItemsToClearModifiedAt.union(Set(responseHandler.receivedByKey.keys).subtracting(responseHandler.idsOfItemsThatRetainModifiedAt))
                    try clearModifiedAtAndSaveContext(keys: keys, clientTimestamp: clientTimestamp, in: context)
                    break
                } catch {
                    if (error as NSError).code == NSManagedObjectMergeError {
                        context.reset()
                        saveAttemptsLeft -= 1
                        if saveAttemptsLeft == 0 {
                            saveError = error
                            break
                        }
                    } else {
                        saveError = error
                        break
                    }
                }

            }
        }
        if let saveError {
            throw saveError
        }

        if let serverTimestamp {
            lastSyncTimestamp = serverTimestamp
            syncDidUpdateData()
        }
    }

    func cleanUpSentItems(_ sent: [Syncable], receivedKeys: Set<String>, clientTimestamp: Date, in context: NSManagedObjectContext) throws -> Set<String> {
        if sent.isEmpty {
            return []
        }
        let keys = sent.compactMap { SyncableSettingAdapter(syncable: $0).uuid }
        let settingsMetadata = try SyncableSettingsMetadataUtils.fetchSettingsMetadata(for: keys, in: context)

        var idsOfItemsToClearModifiedAt = Set<String>()

        for metadata in settingsMetadata {
            guard let adapter = settingsHandlers[Setting(key: metadata.key)] else {
                continue
            }

            if let lastModified = metadata.lastModified, lastModified > clientTimestamp {
                continue
            }
            let isLocalChangeRejectedBySync: Bool = receivedKeys.contains(metadata.key)
            let isPendingDeletion = try adapter.getValue() == nil
            if isPendingDeletion, !isLocalChangeRejectedBySync {
                try adapter.setValue(nil)
                context.delete(metadata)
            } else {
                context.delete(metadata)
                idsOfItemsToClearModifiedAt.insert(metadata.key)
            }
        }

        return idsOfItemsToClearModifiedAt
    }

    private func clearModifiedAtAndSaveContext(keys: Set<String>, clientTimestamp: Date, in context: NSManagedObjectContext) throws {
        let settingsMetadata = try SyncableSettingsMetadataUtils.fetchSettingsMetadata(for: keys, in: context)
        for metadata in settingsMetadata {
            if let lastModified = metadata.lastModified, lastModified < clientTimestamp {
                context.delete(metadata)
            }
        }

        try context.save()
    }

    // MARK: - Private
    private let metadataDatabase: CoreDataDatabase
    private let settingsHandlers: [Setting: any SettingsSyncHandling]

    enum Const {
        static let maxContextSaveRetries = 5
    }

    // MARK: - Test Support

#if DEBUG
    var willSaveContextAfterApplyingSyncResponse: () throws -> Void = {}
#endif
}
