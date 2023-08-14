//
//  SettingsResponseHandler.swift
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

import Bookmarks
import CoreData
import DDGSync
import Foundation

final class SettingsResponseHandler {
    let clientTimestamp: Date?
    let received: [SyncableSettingAdapter]
    let context: NSManagedObjectContext
    let shouldDeduplicateEntities: Bool

    let receivedByKey: [String: SyncableSettingAdapter]
    var metadataByKey: [String: SyncableSettingsMetadata] = [:]

    private let decrypt: (String) throws -> String

    init(
        received: [Syncable],
        clientTimestamp: Date? = nil,
        settingsAdapters: [SettingsProvider.Setting: any SettingsSyncAdapter],
        context: NSManagedObjectContext,
        crypter: Crypting,
        deduplicateEntities: Bool
    ) throws {

        self.clientTimestamp = clientTimestamp
        self.received = received.map(SyncableSettingAdapter.init)
        self.settingsAdapters = settingsAdapters
        self.context = context
        self.shouldDeduplicateEntities = deduplicateEntities

        let secretKey = try crypter.fetchSecretKey()
        self.decrypt = { try crypter.base64DecodeAndDecrypt($0, using: secretKey) }

        var syncablesByUUID: [String: SyncableSettingAdapter] = [:]
        var allUUIDs: Set<String> = []

        self.received.forEach { syncable in
            guard let uuid = syncable.uuid else {
                return
            }
            syncablesByUUID[uuid] = syncable
            allUUIDs.insert(uuid)
        }

        self.receivedByKey = syncablesByUUID

        try SyncableSettingsMetadataUtils.fetchSettingsMetadata(for: allUUIDs, in: context)
            .forEach { metadata in
                metadataByKey[metadata.key] = metadata
            }
    }

    func processReceivedSettings() throws {
        if received.isEmpty {
            return
        }

        for syncable in received {
            try processEntity(with: syncable)
        }
    }

    // MARK: - Private

    private func update(_ setting: SettingsProvider.Setting, with syncable: SyncableSettingAdapter) throws {
        if syncable.isDeleted {
            try settingsAdapters[setting]?.setValue(nil)
        } else {
            let value = try syncable.encryptedValue.flatMap { try decrypt($0) }
            try settingsAdapters[setting]?.setValue(value)
        }
        if let metadata = metadataByKey[setting.rawValue] {
            metadata.lastModified = nil
            context.delete(metadata)
            metadataByKey.removeValue(forKey: setting.rawValue)
        }
    }

    private func processEntity(with syncable: SyncableSettingAdapter) throws {
        guard let syncableKey = syncable.uuid, let setting = SettingsProvider.Setting(rawValue: syncableKey) else {
            return
        }

        if shouldDeduplicateEntities {
            try update(setting, with: syncable)

        } else if let existingMetadata = metadataByKey[syncableKey] {
            let isModifiedAfterSyncTimestamp: Bool = {
                guard let clientTimestamp, let lastModified = existingMetadata.lastModified else {
                    return false
                }
                return lastModified > clientTimestamp
            }()
            if !isModifiedAfterSyncTimestamp {
                try update(setting, with: syncable)
            }
        } else {
            try update(setting, with: syncable)
        }
    }

    private let settingsAdapters: [SettingsProvider.Setting: any SettingsSyncAdapter]
}
