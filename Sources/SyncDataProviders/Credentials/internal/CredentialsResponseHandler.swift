//
//  CredentialsResponseHandler.swift
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


import BrowserServicesKit
import DDGSync
import Foundation
import GRDB

final class CredentialsResponseHandler {
    let clientTimestamp: Date
    let received: [Syncable]
    let secureVault: SecureVault
    let database: Database
    let shouldDeduplicateEntities: Bool

    let receivedByUUID: [String: Syncable]
    let allReceivedIDs: Set<String>

    var credentialsByUUID: [String: SecureVaultModels.SyncableCredentials] = [:]

    private let decrypt: (String) throws -> String

    init(received: [Syncable], clientTimestamp: Date, secureVault: SecureVault, database: Database, crypter: Crypting, deduplicateEntities: Bool) throws {
        self.clientTimestamp = clientTimestamp
        self.received = received
        self.secureVault = secureVault
        self.database = database
        self.shouldDeduplicateEntities = deduplicateEntities

        let secretKey = try crypter.fetchSecretKey()
        self.decrypt = { try crypter.base64DecodeAndDecrypt($0, using: secretKey) }

        var syncablesByUUID: [String: Syncable] = [:]
        var allUUIDs: Set<String> = []

        received.forEach { syncable in
            guard let uuid = syncable.uuid else {
                return
            }
            syncablesByUUID[uuid] = syncable
            allUUIDs.insert(uuid)
        }

        self.allReceivedIDs = allUUIDs
        self.receivedByUUID = syncablesByUUID

        credentialsByUUID = try secureVault.syncableCredentialsForSyncIds(allUUIDs, in: database).reduce(into: .init(), { $0[$1.metadata.uuid] = $1 })
    }

    func processReceivedCredentials() throws {
        if received.isEmpty {
            return
        }

        for syncable in received {
            try processEntity(with: syncable)
        }
    }

    // MARK: - Private

    private func processEntity(with syncable: Syncable) throws {
        guard let syncableUUID = syncable.uuid else {
            throw SyncError.accountAlreadyExists // todo
        }

        if shouldDeduplicateEntities, var deduplicatedEntity = try secureVault.deduplicatedCredentials(in: database, with: syncable, decryptedUsing: decrypt) {

            let oldUUID = deduplicatedEntity.metadata.uuid
            deduplicatedEntity.account?.title = try syncable.encryptedTitle.flatMap(decrypt)
            deduplicatedEntity.metadata.uuid = syncableUUID
            try secureVault.storeSyncableCredentials(deduplicatedEntity, in: database)

            credentialsByUUID.removeValue(forKey: oldUUID)
            credentialsByUUID[syncableUUID] = deduplicatedEntity

        } else if var existingEntity = credentialsByUUID[syncableUUID] {
            let isModifiedAfterSyncTimestamp: Bool = {
                guard let modifiedAt = existingEntity.metadata.lastModified else {
                    return false
                }
                return modifiedAt > clientTimestamp
            }()
            if !isModifiedAfterSyncTimestamp {
                if syncable.isDeleted {
                    try secureVault.deleteSyncableCredentials(existingEntity, in: database)
                } else {
                    try existingEntity.update(with: syncable, decryptedUsing: decrypt)
                    existingEntity.metadata.lastModified = nil
                    try secureVault.storeSyncableCredentials(existingEntity, in: database)
                }
            }

        } else if !syncable.isDeleted {

            let newEntity = try SecureVaultModels.SyncableCredentials(syncable: syncable, decryptedUsing: decrypt)
            assert(newEntity.metadata.lastModified == nil, "lastModified should be nil for a new metadata entity")
            try secureVault.storeSyncableCredentials(newEntity, in: database)
            credentialsByUUID[syncableUUID] = newEntity
        }
    }
}

extension SecureVaultModels.SyncableCredentials {

    init(syncable: Syncable, decryptedUsing decrypt: (String) throws -> String) throws {
        guard let uuid = syncable.uuid else {
            throw SyncError.accountAlreadyExists
        }

        let title = try syncable.encryptedTitle.flatMap { try decrypt($0) }
        let username = try syncable.encryptedUsername.flatMap { try decrypt($0) }
        let domain = try syncable.encryptedDomain.flatMap { try decrypt($0) }
        let notes = try syncable.encryptedNotes.flatMap { try decrypt($0) }
        let password = try syncable.encryptedPassword.flatMap { try decrypt($0) }

        let account = SecureVaultModels.WebsiteAccount(title: title, username: username, domain: domain, notes: notes)
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: password?.data(using: .utf8))
        self.init(uuid: uuid, credentials: credentials, lastModified: nil)
    }

    mutating func update(with syncable: Syncable, decryptedUsing decrypt: (String) throws -> String) throws {
        let title = try syncable.encryptedTitle.flatMap(decrypt)
        let domain = try syncable.encryptedDomain.flatMap(decrypt)
        let username = try syncable.encryptedUsername.flatMap(decrypt)
        let password = try syncable.encryptedPassword.flatMap(decrypt)?.data(using: .utf8)
        let notes = try syncable.encryptedNotes.flatMap(decrypt)

        if account == nil {
            account = .init(title: title, username: username, domain: domain, notes: notes)
        } else {
            account?.title = title
            account?.domain = domain
            account?.username = username
            account?.notes = notes
        }

        assert(account != nil)

        if credentialsRecord == nil {
            credentialsRecord = .init(credentials: .init(account: account!, password: password))
        } else {
            credentialsRecord?.password = password
        }
    }
}
