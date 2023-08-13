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
import Combine
import DDGSync
import Persistence

public final class SettingsProvider: DataProvider {

    public enum Setting: String, CaseIterable {
        case duckAddress
    }

    public init(
        metadataDatabase: CoreDataDatabase,
        metadataStore: SyncMetadataStore,
        settingsAdapters: [Setting: any SettingsSyncAdapter],
        syncDidUpdateData: @escaping () -> Void
    ) throws {
        self.metadataDatabase = metadataDatabase
        self.settingsAdapters = settingsAdapters
        super.init(feature: .init(name: "settings"), metadataStore: metadataStore, syncDidUpdateData: syncDidUpdateData)
    }

    // MARK: - DataProviding

    public override func prepareForFirstSync() throws {
        lastSyncTimestamp = nil
        // todo: set last modified on all settings to current date
    }

    public override func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let modifiedSettings = try SyncableSettingsMetadataUtils.fetchMetadataForSettingsPendingSync(in: context)

        let encryptionKey = try crypter.fetchSecretKey()

        return try modifiedSettings.compactMap { modifiedSetting -> Syncable? in
            guard let setting = Setting(rawValue: modifiedSetting.key), let adapter = settingsAdapters[setting] else {
                // todo: error
                return nil
            }
            let value = try adapter.getValue()
            return try Syncable(
                setting: setting,
                value: value,
                lastModified: modifiedSetting.lastModified,
                encryptedUsing: { try crypter.encryptAndBase64Encode($0, using: encryptionKey)}
            )
        }
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
