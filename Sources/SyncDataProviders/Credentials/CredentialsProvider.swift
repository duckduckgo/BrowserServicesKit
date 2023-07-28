//
//  CredentialsProvider.swift
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
import SecureStorage

public final class CredentialsProvider: DataProvider {

    public init(
        secureVaultFactory: AutofillVaultFactory = AutofillSecureVaultFactory,
        secureVaultErrorReporter: SecureVaultErrorReporting,
        metadataStore: SyncMetadataStore,
        syncDidUpdateData: @escaping () -> Void
    ) throws {
        self.secureVaultFactory = secureVaultFactory
        self.secureVaultErrorReporter = secureVaultErrorReporter
        super.init(feature: .init(name: "credentials"), metadataStore: metadataStore, syncDidUpdateData: syncDidUpdateData)
    }

    // MARK: - DataProviding

    public override func prepareForFirstSync() throws {
        lastSyncTimestamp = nil
        let secureVault = try secureVaultFactory.makeVault(errorReporter: secureVaultErrorReporter)
        try secureVault.inDatabaseTransaction { database in

            let accountIds = try Row.fetchAll(
                database,
                sql: "SELECT \(SecureVaultModels.WebsiteAccount.Columns.id.name) FROM \(SecureVaultModels.WebsiteAccount.databaseTableName)"
            ).compactMap { row -> Int64? in
                row[SecureVaultModels.WebsiteAccount.Columns.id.name]
            }

            let credentialsMetadata = try SecureVaultModels.SyncableCredentialsRecord.fetchAll(database)
            var accountIdsSet = Set(accountIds)
            let currentTimestamp = Date()

            for i in 0..<credentialsMetadata.count {
                var metadataObject = credentialsMetadata[i]
                metadataObject.lastModified = currentTimestamp
                try metadataObject.update(database)

                if let accountId = metadataObject.objectId {
                    accountIdsSet.remove(accountId)
                }
            }

            if accountIdsSet.count > 0 {
                assertionFailure("Syncable Credentials metadata objects not present for all Website Account objects")

                self.handleSyncError(SyncError.credentialsMetadataMissingBeforeFirstSync)

                for accountId in accountIdsSet {
                    try SecureVaultModels.SyncableCredentialsRecord(objectId: accountId, lastModified: Date()).insert(database)
                }
            }
        }
    }

    public override func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        let secureVault = try secureVaultFactory.makeVault(errorReporter: secureVaultErrorReporter)
        let syncableCredentials = try secureVault.modifiedSyncableCredentials()
        let encryptionKey = try crypter.fetchSecretKey()
        return try syncableCredentials.map { credentials in
            try Syncable.init(
                syncableCredentials: credentials,
                encryptedUsing: { try crypter.encryptAndBase64Encode($0, using: encryptionKey) }
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
        var saveError: Error?

        let secureVault = try secureVaultFactory.makeVault(errorReporter: secureVaultErrorReporter)
        let clientTimestampMilliseconds = clientTimestamp.withMillisecondPrecision
        var saveAttemptsLeft = Const.maxContextSaveRetries

        while true {
            do {
                try secureVault.inDatabaseTransaction { database in

                    let responseHandler = try CredentialsResponseHandler(
                        received: received,
                        clientTimestamp: clientTimestampMilliseconds,
                        secureVault: secureVault,
                        database: database,
                        crypter: crypter,
                        deduplicateEntities: isInitial)

                    let idsOfItemsToClearModifiedAt = try self.cleanUpSentItems(
                        sent,
                        receivedUUIDs: Set(responseHandler.allReceivedIDs),
                        clientTimestamp: clientTimestampMilliseconds,
                        in: database
                    )

                    try responseHandler.processReceivedCredentials()
#if DEBUG
                    try self.willSaveContextAfterApplyingSyncResponse()
#endif

                    let uuids = idsOfItemsToClearModifiedAt.union(responseHandler.allReceivedIDs)
                    try self.clearModifiedAt(uuids: uuids, clientTimestamp: clientTimestampMilliseconds, in: database)
                }
                break
            } catch {
                if case SecureStorageError.databaseError(let cause) = error, let databaseError = cause as? DatabaseError {
                    switch databaseError {
                    case .SQLITE_BUSY, .SQLITE_LOCKED:
                        saveAttemptsLeft -= 1
                        if saveAttemptsLeft == 0 {
                            saveError = error
                            break
                        }
                    default:
                        saveError = error
                        break
                    }
                } else {
                    saveError = error
                    break
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

    func cleanUpSentItems(_ sent: [Syncable], receivedUUIDs: Set<String>, clientTimestamp: Date, in database: Database) throws -> Set<String> {
        if sent.isEmpty {
            return []
        }

        let identifiers = sent.compactMap(\.uuid)
        var idsOfItemsToClearModifiedAt = Set<String>()

        let syncableCredentialsRecords = try SecureVaultModels.SyncableCredentialsRecord
            .filter(identifiers.contains(SecureVaultModels.SyncableCredentialsRecord.Columns.uuid))
            .fetchAll(database)

        for metadataRecord in syncableCredentialsRecords {
            if let modifiedAt = metadataRecord.lastModified, modifiedAt.compareWithMillisecondPrecision(to: clientTimestamp) == .orderedDescending {
                continue
            }
            let isLocalChangeRejectedBySync: Bool = receivedUUIDs.contains(metadataRecord.uuid)
            if metadataRecord.objectId == nil, !isLocalChangeRejectedBySync {
                try metadataRecord.delete(database)
            } else {
                idsOfItemsToClearModifiedAt.insert(metadataRecord.uuid)
            }
        }

        return idsOfItemsToClearModifiedAt
    }

    private func clearModifiedAt(uuids: Set<String>, clientTimestamp: Date, in database: Database) throws {

        let request = SecureVaultModels.SyncableCredentialsRecord
            .filter(uuids.contains(SecureVaultModels.SyncableCredentialsRecord.Columns.uuid))
            .filter(SecureVaultModels.SyncableCredentialsRecord.Columns.lastModified < clientTimestamp)

        let metadataObjects = try SecureVaultModels.SyncableCredentialsRecord.fetchAll(database, request)

        for i in 0..<metadataObjects.count {
            var metadata = metadataObjects[i]
            metadata.lastModified = nil
            try metadata.update(database)
        }
    }

    // MARK: - Private

    private let secureVaultFactory: AutofillVaultFactory
    private let secureVaultErrorReporter: SecureVaultErrorReporting

    enum Const {
        static let maxContextSaveRetries = 5
    }

    // MARK: - Test support

#if DEBUG
    var willSaveContextAfterApplyingSyncResponse: () throws -> Void = {}
#endif

}
