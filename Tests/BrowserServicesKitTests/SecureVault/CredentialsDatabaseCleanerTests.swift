//
//  CredentialsDatabaseCleanerTests.swift
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
import GRDB
@testable import BrowserServicesKit

final class MockEventMapper: EventMapping<CredentialsCleanupError> {
    static var errors: [Error] = []

    public init() {
        super.init { event, _, _, _ in
            Self.errors.append(event.cleanupError)
        }
    }

    deinit {
        Self.errors = []
    }

    override init(mapping: @escaping EventMapping<CredentialsCleanupError>.Mapping) {
        fatalError("Use init()")
    }
}

final class MockSecureVaultErrorReporter: SecureVaultErrorReporting {
    var _secureVaultInitFailed: (SecureVaultError) -> Void = { _ in }
    func secureVaultInitFailed(_ error: SecureVaultError) {
        _secureVaultInitFailed(error)
    }
}

final class CredentialsDatabaseCleanerTests: XCTestCase {
    let simpleL1Key = "simple-key".data(using: .utf8)!
    var databaseLocation: URL!
    var databaseProvider: DefaultDatabaseProvider!

    var secureVaultFactory: SecureVaultFactory!
    var secureVault: SecureVault!

    var location: URL!
    var databaseCleaner: CredentialsDatabaseCleaner!
    var eventMapper: MockEventMapper!

    override func setUpWithError() throws {
        try super.setUpWithError()

        databaseLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        databaseProvider = try DefaultDatabaseProvider(file: databaseLocation, key: simpleL1Key)
        secureVaultFactory = TestSecureVaultFactory(databaseProvider: databaseProvider)
        secureVault = try secureVaultFactory.makeVault(errorReporter: nil)
        _ = try secureVault.authWith(password: "abcd".data(using: .utf8)!)

        eventMapper = MockEventMapper()
    }

    override func tearDownWithError() throws {
        try deleteDbFile()
        try super.tearDownWithError()
    }

    func testWhenThereAreNoConflictsThenCleanerContextIsSavedOnce() throws {
        databaseCleaner = CredentialsDatabaseCleaner(
            secureVaultFactory: secureVaultFactory,
            secureVaultErrorReporter: MockSecureVaultErrorReporter(),
            errorEvents: eventMapper
        )

        try secureVault.storeCredentials(domain: "1", username: "1")
        try secureVault.storeCredentials(domain: "2", username: "2")

        var syncableCredentialsMetadata = try databaseProvider.db.read { database in
            try SecureVaultModels.SyncableCredentialsRecord.fetchAll(database)
        }

        XCTAssertEqual(syncableCredentialsMetadata.count, 2)

        let accountId = try XCTUnwrap(syncableCredentialsMetadata.first?.objectId)
        try secureVault.deleteWebsiteCredentialsFor(accountId: accountId)

        syncableCredentialsMetadata = try databaseProvider.db.read { database in
            try SecureVaultModels.SyncableCredentialsRecord.fetchAll(database)
        }

        XCTAssertEqual(syncableCredentialsMetadata.count, 2)

        databaseCleaner.removeSyncableCredentialsMetadataPendingDeletion()

        syncableCredentialsMetadata = try databaseProvider.db.read { database in
            try SecureVaultModels.SyncableCredentialsRecord.fetchAll(database)
        }

        XCTAssertTrue(MockEventMapper.errors.isEmpty)
        XCTAssertEqual(syncableCredentialsMetadata.count, 1)
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
}

class TestSecureVaultFactory: SecureVaultFactory {

    var mockCryptoProvider = NoOpCryptoProvider()
    var mockKeystoreProvider = MockKeystoreProvider()
    var databaseProvider: DefaultDatabaseProvider

    init(databaseProvider: DefaultDatabaseProvider) {
        self.databaseProvider = databaseProvider
        mockKeystoreProvider._l1Key = "l1".data(using: .utf8)
        mockKeystoreProvider._encryptedL2Key = "encrypted".data(using: .utf8)
        super.init()
    }

    override func makeCryptoProvider() -> SecureVaultCryptoProvider {
        mockCryptoProvider
    }

    override func makeKeyStoreProvider() -> SecureVaultKeyStoreProvider {
        mockKeystoreProvider
    }

    override func makeDatabaseProvider(key: Data) throws -> SecureVaultDatabaseProvider {
        databaseProvider
    }
}

extension SecureVault {
    func storeCredentials(domain: String? = nil, username: String? = nil, password: String? = nil, notes: String? = nil) throws {
        let passwordData = password.flatMap { $0.data(using: .utf8) }
        let account = SecureVaultModels.WebsiteAccount(username: username, domain: domain, notes: notes)
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
        try storeWebsiteCredentials(credentials)
    }
}

