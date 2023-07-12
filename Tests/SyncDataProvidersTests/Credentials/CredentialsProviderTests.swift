//
//  CredentialsProviderTests.swift
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

import XCTest
import Common
import DDGSync
import GRDB
import Persistence
@testable import BrowserServicesKit
@testable import SyncDataProviders

final class CredentialsProviderTests: XCTestCase {

    let simpleL1Key = "simple-key".data(using: .utf8)!
    var databaseLocation: URL!
    var databaseProvider: DefaultDatabaseProvider!

    var metadataDatabase: CoreDataDatabase!
    var metadataDatabaseLocation: URL!

    var crypter = CryptingMock()
    var provider: LoginsProvider!

    var secureVaultFactory: SecureVaultFactory!
    var secureVault: SecureVault!

    func setUpSyncMetadataDatabase() {
        metadataDatabaseLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = DDGSync.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "SyncMetadata") else {
            XCTFail("Failed to load model")
            return
        }
        metadataDatabase = CoreDataDatabase(name: className, containerLocation: metadataDatabaseLocation, model: model)
        metadataDatabase.loadStore()
    }

    func deleteDbFile() throws {
        do {
            let dbFileContainer = databaseLocation.deletingLastPathComponent()
            for file in try FileManager.default.contentsOfDirectory(atPath: dbFileContainer.path) {
                guard ["db", "bak"].contains((file as NSString).pathExtension) else { continue }
                try FileManager.default.removeItem(atPath: dbFileContainer.appendingPathComponent(file).path)
            }

        } catch let error as NSError {
            // File not found
            if error.domain != NSCocoaErrorDomain || error.code != 4 {
                throw error
            }
        }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()

        databaseLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        databaseProvider = try DefaultDatabaseProvider(file: databaseLocation, key: simpleL1Key)
        secureVaultFactory = TestSecureVaultFactory(databaseProvider: databaseProvider)
        try makeSecureVault()

        setUpSyncMetadataDatabase()

        provider = try LoginsProvider(
            secureVaultFactory: secureVaultFactory,
            metadataStore: LocalSyncMetadataStore(database: metadataDatabase),
            reloadLoginsAfterSync: {}
        )
    }

    override func tearDownWithError() throws {
        try deleteDbFile()

        try? metadataDatabase.tearDown(deleteStores: true)
        metadataDatabase = nil
        try? FileManager.default.removeItem(at: metadataDatabaseLocation)

        try super.tearDownWithError()
    }

    func testThatLastSyncTimestampIsNilByDefault() {
        XCTAssertNil(provider.lastSyncTimestamp)
    }

    func testThatLastSyncTimestampIsPersisted() {
        provider.lastSyncTimestamp = "12345"
        XCTAssertEqual(provider.lastSyncTimestamp, "12345")
    }

    func testThatPrepareForFirstSyncClearsLastSyncTimestampAndSetsModifiedAtForAllCredentials() throws {

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeCredentialsMetadata("1", in: database)
            try self.secureVault.storeCredentialsMetadata("2", in: database)
            try self.secureVault.storeCredentialsMetadata("3", in: database)
            try self.secureVault.storeCredentialsMetadata("4", in: database)
        }

        var syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertTrue(syncableCredentials.allSatisfy { $0.metadata.lastModified == nil })

        let date = Date().withMillisecondPrecision
        try provider.prepareForFirstSync()

        XCTAssertNil(provider.lastSyncTimestamp)

        syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 4)
        XCTAssertTrue(syncableCredentials.allSatisfy { $0.metadata.lastModified! >= date })
    }

    func testThatFetchChangedObjectsReturnsAllObjectsWithNonNilModifiedAt() async throws {

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeCredentialsMetadata("1", lastModified: Date(), in: database)
            try self.secureVault.storeCredentialsMetadata("2", in: database)
            try self.secureVault.storeCredentialsMetadata("3", lastModified: Date(), in: database)
            try self.secureVault.storeCredentialsMetadata("4", in: database)
        }

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        XCTAssertEqual(
            Set(changedObjects.compactMap(\.uuid)),
            Set(["1", "3"])
        )
    }

    func testWhenCredentialsAreSoftDeletedThenFetchChangedObjectsContainsDeletedSyncable() async throws {

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeCredentialsMetadata("1", in: database)
            try self.secureVault.storeCredentialsMetadata("2", in: database)
            try self.secureVault.storeCredentialsMetadata("3", in: database)
            try self.secureVault.storeCredentialsMetadata("4", in: database)
        }

        try secureVault.deleteWebsiteCredentialsFor(accountId: 2)

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        XCTAssertEqual(changedObjects.count, 1)

        let syncable = try XCTUnwrap(changedObjects.first)

        XCTAssertTrue(syncable.isDeleted)
        XCTAssertEqual(syncable.uuid, "2")
    }

    func testThatSentItemsAreProperlyCleanedUp() async throws {

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeCredentialsMetadata("1", lastModified: Date(), in: database)
            try self.secureVault.storeCredentialsMetadata("2", lastModified: Date(), in: database)
            try self.secureVault.storeCredentialsMetadata("3", lastModified: Date(), in: database)
            try self.secureVault.storeCredentialsMetadata("4", lastModified: Date(), in: database)
        }

        try secureVault.deleteWebsiteCredentialsFor(accountId: 2)

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 3)
        XCTAssertTrue(syncableCredentials.allSatisfy { $0.metadata.lastModified == nil })
    }

    // MARK: - Initial Sync

    func testThatInitialSyncIntoEmptyDatabaseClearsModifiedAtFromAllReceivedObjects() async throws {

        let received: [Syncable] = [
            .credentials(id: "1"),
            .credentials(id: "2"),
            .credentials(id: "3"),
            .credentials(id: "4"),
            .credentials(id: "5")
        ]

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 5)
        XCTAssertTrue(syncableCredentials.allSatisfy { $0.metadata.lastModified == nil })
    }

    func testThatInitialSyncClearsModifiedAtFromDeduplicatedCredential() async throws {

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeCredentialsMetadata("1", lastModified: Date().withMillisecondPrecision, in: database)
        }

        let received: [Syncable] = [
            .credentials(id: "1")
        ]

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableCredentials = try fetchAllSyncableCredentials()
        let credential = try XCTUnwrap(syncableCredentials.first)
        XCTAssertNil(credential.metadata.lastModified)
    }

    func testWhenThereIsMergeConflictDuringInitialSyncThenSyncResponseHandlingIsRetried() async throws {
        throw XCTSkip()
    }

    // MARK: - Regular Sync

    func testWhenObjectDeleteIsSentAndTheSameObjectUpdateIsReceivedThenObjectIsNotDeleted() async throws {

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeCredentialsMetadata("1", in: database)
        }

        try secureVault.deleteWebsiteCredentialsFor(accountId: 1)

        let received: [Syncable] = [
            .credentials(id: "1", username: "2")
        ]

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().withMillisecondPrecision, serverTimestamp: "1234", crypter: crypter)

        let syncableCredentials = try fetchAllSyncableCredentials()
        let updatedCredential = try XCTUnwrap(syncableCredentials.first)
        XCTAssertEqual(syncableCredentials.count, 1)
        XCTAssertNil(updatedCredential.metadata.lastModified)
        XCTAssertEqual(updatedCredential.account?.username, "2")
    }

    func testWhenObjectWasSentAndThenDeletedLocallyAndAnUpdateIsReceivedThenTheObjectIsDeleted() async throws {

        let modifiedAt = Date().withMillisecondPrecision

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeCredentialsMetadata("1", lastModified: modifiedAt, in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        try secureVault.deleteWebsiteCredentialsFor(accountId: 1)

        let received: [Syncable] = [
            .credentials(id: "1", username: "2")
        ]

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: modifiedAt.advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let syncableCredentials = try fetchAllSyncableCredentials()
        let deletedCredential = try XCTUnwrap(syncableCredentials.first)
        XCTAssertNotNil(deletedCredential.metadata.lastModified)
        XCTAssertNil(deletedCredential.metadata.objectId)
    }

    func testWhenObjectWasUpdatedLocallyAfterStartingSyncThenRemoteChangesAreDropped() async throws {

        let modifiedAt = Date().withMillisecondPrecision

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeCredentialsMetadata("1", lastModified: modifiedAt, in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        let received: [Syncable] = [
            .credentials(id: "1", username: "2")
        ]

        var credentials = try XCTUnwrap(try secureVault.websiteCredentialsFor(accountId: 1))
        credentials.password = "updated".data(using: .utf8)
        try secureVault.storeWebsiteCredentials(credentials)
        var updateTimestamp: Date?
        try secureVault.inDatabaseTransaction({ database in
            updateTimestamp = try self.secureVault.websiteCredentialsMetadataForAccountId(1, in: database)?.metadata.lastModified
        })

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: modifiedAt.advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let syncableCredentials = try fetchAllSyncableCredentials()
        let updatedCredential = try XCTUnwrap(syncableCredentials.first)
        XCTAssertEqual(updatedCredential.metadata.lastModified, updateTimestamp)
        XCTAssertEqual(updatedCredential.account?.username, "1")
        XCTAssertEqual(updatedCredential.rawCredentials?.password, credentials.password)
    }


    func testWhenThereIsMergeConflictDuringRegularSyncThenSyncResponseHandlingIsRetried() async throws {
        throw XCTSkip()
    }

    // MARK: - Helpers

    func makeSecureVault() throws {
        secureVault = try secureVaultFactory.makeVault(errorReporter: nil)
        _ = try secureVault.authWith(password: "abcd".data(using: .utf8)!)
    }

    func fetchAllSyncableCredentials() throws -> [SecureVaultModels.SyncableWebsiteCredentialInfo] {
        try databaseProvider.db.read { database in
            try SecureVaultModels.SyncableWebsiteCredentialInfo.fetchAll(database)
        }
    }
}

extension SecureVaultModels.SyncableWebsiteCredentialInfo {

    static func fetchAll(_ database: Database) throws -> [SecureVaultModels.SyncableWebsiteCredentialInfo] {
        try SecureVaultModels.SyncableWebsiteCredential
            .including(optional: SecureVaultModels.SyncableWebsiteCredential.account)
            .including(optional: SecureVaultModels.SyncableWebsiteCredential.rawCredentials)
            .asRequest(of: SecureVaultModels.SyncableWebsiteCredentialInfo.self)
            .fetchAll(database)
    }
}

extension SecureVault {
    func storeCredentials(domain: String? = nil, username: String? = nil, password: String? = nil, notes: String? = nil) throws {
        let passwordData = password.flatMap { $0.data(using: .utf8) }
        let account = SecureVaultModels.WebsiteAccount(username: username, domain: domain, notes: notes)
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
        try storeWebsiteCredentials(credentials)
    }

    func storeCredentialsMetadata(
        _ id: String = UUID().uuidString,
        domain: String? = nil,
        username: String? = nil,
        password: String? = nil,
        notes: String? = nil,
        lastModified: Date? = nil,
        in database: Database? = nil
    ) throws {
        let domain = domain ?? id
        let username = username ?? id
        let password = password ?? id
        let notes = notes ?? id

        let passwordData = password.data(using: .utf8)
        let account = SecureVaultModels.WebsiteAccount(username: username, domain: domain, notes: notes)
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
        let metadata = SecureVaultModels.SyncableWebsiteCredentialInfo(id: id, credentials: credentials, lastModified: lastModified?.withMillisecondPrecision)
        if let database {
            try storeWebsiteCredentialsMetadata(metadata, in: database)
        } else {
            try inDatabaseTransaction { try storeWebsiteCredentialsMetadata(metadata, in: $0) }
        }
    }
}
