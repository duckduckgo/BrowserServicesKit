//
//  SecureVaultSyncableCredentialsMigrationPerformanceTests.swift
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

import GRDB
import XCTest
@testable import BrowserServicesKit

class SecureVaultSyncableCredentialsMigrationPerformanceTests: XCTestCase {

    let simpleL1Key = "simple-key".data(using: .utf8)!
    var databaseLocation: URL!
    var provider: DefaultDatabaseProvider!

    func testV10Migration() throws {
        measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
            do {
                databaseLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
                provider = try DefaultDatabaseProvider(file: databaseLocation, key: simpleL1Key, customMigrations: { migrator in
                    migrator.registerMigration("v1", migrate: DefaultDatabaseProvider.migrateV1(database:))
                    migrator.registerMigration("v2", migrate: DefaultDatabaseProvider.migrateV2(database:))
                    migrator.registerMigration("v3", migrate: DefaultDatabaseProvider.migrateV3(database:))
                    migrator.registerMigration("v4", migrate: DefaultDatabaseProvider.migrateV4(database:))
                    migrator.registerMigration("v5", migrate: DefaultDatabaseProvider.migrateV5(database:))
                    migrator.registerMigration("v6", migrate: DefaultDatabaseProvider.migrateV6(database:))
                    migrator.registerMigration("v7", migrate: DefaultDatabaseProvider.migrateV7(database:))
                    migrator.registerMigration("v8", migrate: DefaultDatabaseProvider.migrateV8(database:))
                    migrator.registerMigration("v9", migrate: DefaultDatabaseProvider.migrateV9(database:))
                })

                try provider.db.write { database in
                    for i in 1...1000 {
                        var account = SecureVaultModels.WebsiteAccount(username: "username\(i)", domain: "domain\(i)")
                        account.id = try XCTUnwrap(try account.insertAndFetch(database)?.id)

                        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password\(i)".data(using: .utf8))
                        let credentialsRecord = SecureVaultModels.WebsiteCredentialsRecord(credentials: credentials)
                        try credentialsRecord.insert(database)
                    }
                }

                var migrator = DatabaseMigrator()
                migrator.registerMigration("v10", migrate: DefaultDatabaseProvider.migrateV10(database:))

                startMeasuring()
                try migrator.migrate(provider.db)
                stopMeasuring()

                let syncableCredentials = try provider.db.read { database in
                    try SecureVaultModels.SyncableCredentials.query.fetchAll(database)
                }
                XCTAssertEqual(syncableCredentials.count, 1000)
                try deleteDbFile()

            } catch {
                XCTFail("migration failed: \(error)")
            }
        }

    }

    // MARK: - Private

    private func deleteDbFile() throws {
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
