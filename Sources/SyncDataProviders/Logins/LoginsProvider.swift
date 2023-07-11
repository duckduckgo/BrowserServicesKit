//
//  LoginsProvider.swift
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
import GRDB

public final class LoginsProvider: DataProviding {

    public init(secureVaultFactory: SecureVaultFactory = .default, metadataStore: SyncMetadataStore, reloadLoginsAfterSync: @escaping () -> Void) throws {
        self.secureVaultFactory = secureVaultFactory
        self.metadataStore = metadataStore
        try self.metadataStore.registerFeature(named: feature.name)
        self.reloadLoginsAfterSync = reloadLoginsAfterSync
        syncErrorPublisher = syncErrorSubject.eraseToAnyPublisher()
    }

    public let syncErrorPublisher: AnyPublisher<Error, Never>

    // MARK: - DataProviding

    public let feature: Feature = .init(name: "credentials")

    public var lastSyncTimestamp: String? {
        get {
            metadataStore.timestamp(forFeatureNamed: feature.name)
        }
        set {
            metadataStore.updateTimestamp(newValue, forFeatureNamed: feature.name)
        }
    }

    public func prepareForFirstSync() throws {
        lastSyncTimestamp = nil
        let secureVault = try secureVaultFactory.makeVault(errorReporter: nil)
        try secureVault.inDatabaseTransaction { database in
            try database.execute(sql: """
                UPDATE
                    \(SecureVaultModels.SyncableWebsiteCredential.databaseTableName)
                SET
                    \(SecureVaultModels.SyncableWebsiteCredential.Columns.lastModified.name) = ?
            """, arguments: [Date()])
        }
    }

    public func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        let secureVault = try secureVaultFactory.makeVault(errorReporter: nil)
        var date = Date()
        let metadata = try secureVault.modifiedWebsiteCredentialsMetadata()
        print("Fetching took \(Date().timeIntervalSince(date)) s")
        date = Date()
        let encryptionKey = try crypter.fetchSecretKey()
        let syncables = try metadata.map { try Syncable.init(metadata: $0, encryptedUsing: { try crypter.encryptAndBase64Encode($0, using: encryptionKey)}) }
        print("Syncable population took \(Date().timeIntervalSince(date)) s")
        return syncables
    }

    public func handleInitialSyncResponse(received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        try await handleSyncResponse(isInitial: true, sent: [], received: received, clientTimestamp: clientTimestamp, serverTimestamp: serverTimestamp, crypter: crypter)
    }

    public func handleSyncResponse(sent: [Syncable], received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        try await handleSyncResponse(isInitial: false, sent: sent, received: received, clientTimestamp: clientTimestamp, serverTimestamp: serverTimestamp, crypter: crypter)
    }

    public func handleSyncError(_ error: Error) {
        syncErrorSubject.send(error)
    }

    // MARK: - Internal

    func handleSyncResponse(isInitial: Bool, sent: [Syncable], received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {

        let secureVault = try secureVaultFactory.makeVault(errorReporter: nil)
        let clientTimestampMilliseconds = clientTimestamp.withMillisecondPrecision

        try secureVault.inDatabaseTransaction { database in

            let responseHandler = try LoginsResponseHandler(
                received: received,
                clientTimestamp: clientTimestampMilliseconds,
                secureVault: secureVault,
                database: database,
                crypter: crypter,
                deduplicateEntities: isInitial)

            let idsOfItemsToClearModifiedAt = try self.cleanUpSentItems(
                sent,
                receivedUUIDs: Set(responseHandler.receivedByUUID.keys),
                clientTimestamp: clientTimestampMilliseconds,
                secureVault: secureVault,
                in: database
            )

            try responseHandler.processReceivedCredentials()
#if DEBUG
            self.willSaveContextAfterApplyingSyncResponse()
#endif

            let uuids = idsOfItemsToClearModifiedAt.union(responseHandler.receivedByUUID.keys)
            try self.clearModifiedAt(uuids: uuids, clientTimestamp: clientTimestampMilliseconds, secureVault: secureVault, in: database)
        }

        if let serverTimestamp {
            lastSyncTimestamp = serverTimestamp
            reloadLoginsAfterSync()
        }
    }

    func cleanUpSentItems(_ sent: [Syncable], receivedUUIDs: Set<String>, clientTimestamp: Date, secureVault: SecureVault, in database: Database) throws -> Set<String> {
        if sent.isEmpty {
            return []
        }

        let identifiers = sent.compactMap(\.uuid)
        var idsOfItemsToClearModifiedAt = Set<String>()

        let metadataObjects = try SecureVaultModels.SyncableWebsiteCredential.fetchAll(database, keys: identifiers)
        for metadata in metadataObjects {
            if let modifiedAt = metadata.lastModified, modifiedAt > clientTimestamp {
                continue
            }
            let isLocalChangeRejectedBySync: Bool = receivedUUIDs.contains(metadata.id)
            if metadata.objectId == nil, !isLocalChangeRejectedBySync {
                try metadata.delete(database)
            } else {
                idsOfItemsToClearModifiedAt.insert(metadata.id)
            }
        }

        return idsOfItemsToClearModifiedAt
    }

    private func clearModifiedAt(uuids: Set<String>, clientTimestamp: Date, secureVault: SecureVault, in database: Database) throws {

        let request = SecureVaultModels.SyncableWebsiteCredential
            .filter(keys: uuids)
            .filter(SecureVaultModels.SyncableWebsiteCredential.Columns.lastModified < clientTimestamp)

        let metadataObjects = try SecureVaultModels.SyncableWebsiteCredential.fetchAll(database, request)

        for i in 0..<metadataObjects.count {
            var metadata = metadataObjects[i]
            metadata.lastModified = nil
            try metadata.update(database)
        }
    }

    // MARK: - Private

    private let secureVaultFactory: SecureVaultFactory
    private let metadataStore: SyncMetadataStore
    private let reloadLoginsAfterSync: () -> Void
    private let syncErrorSubject = PassthroughSubject<Error, Never>()

    // MARK: - Test support

#if DEBUG
    var willSaveContextAfterApplyingSyncResponse: () -> Void = {}
#endif

}

extension Date {
    /**
     * Rounds receiver to milliseconds.
     *
     * Because SQLite stores timestamps with millisecond precision, comparing against
     * microsecond-precision Date type may produce unexpected results. Hence sync timestamp
     * is rounded to milliseconds.
     */
    var withMillisecondPrecision: Date {
        Date(timeIntervalSince1970: TimeInterval(Int(timeIntervalSince1970 * 1_000_000) / 1_000) / 1_000)
    }
}
