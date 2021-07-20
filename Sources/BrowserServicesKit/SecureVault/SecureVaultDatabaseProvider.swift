//
//  SecureVaultDatabaseProvider.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import GRDB

protocol SecureVaultDatabaseProvider {

    func accounts() throws -> [SecureVaultModels.WebsiteAccount]

    func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) throws

    func websiteCredentialsForAccountId(_ accountId: Int64) throws -> SecureVaultModels.WebsiteCredentials?

    func websiteAccountsForDomain(_ domain: String) throws -> [SecureVaultModels.WebsiteAccount]

    func deleteWebsiteCredentialsForAccountId(_ accountId: Int64) throws

}

final class DefaultDatabaseProvider: SecureVaultDatabaseProvider {

    enum DbError: Error {

        case unableToDetermineStorageDirectory
        case unableToGetDatabaseKey

    }

    let db: DatabaseQueue

    init(key: Data) throws {
        var config = Configuration()
        config.prepareDatabase {
            try $0.usePassphrase(key)
        }

        let file = try Self.dbFile()
        db = try DatabaseQueue(path: file.path, configuration: config)

        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1", migrate: Self.migrateV1(database:))
        migrator.registerMigration("v2", migrate: Self.migrateV2(database:))
        migrator.registerMigration("v3", migrate: Self.migrateV3(database:))
        // ... add more migrations here ...
        try migrator.migrate(db)
    }

    func accounts() throws -> [SecureVaultModels.WebsiteAccount] {
        return try db.read {
            return try SecureVaultModels.WebsiteAccount
                .fetchAll($0)
        }
    }

    func websiteAccountsForDomain(_ domain: String) throws -> [SecureVaultModels.WebsiteAccount] {
        return try db.read {
            return try SecureVaultModels.WebsiteAccount
                .filter(SecureVaultModels.WebsiteAccount.Columns.domain.like(domain))
                .fetchAll($0)
        }
    }

    func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) throws {

        if let id = credentials.account.id {
            try updateWebsiteCredentials(credentials, usingId: id)
        } else {
            try insertWebsiteCredentials(credentials)
        }
    }

    func deleteWebsiteCredentialsForAccountId(_ accountId: Int64) throws {
        guard let credentials = try websiteCredentialsForAccountId(accountId) else {
            return
        }

        try db.write {
            try $0.execute(sql: """
                DELETE FROM
                    \(SecureVaultModels.WebsiteCredentials.databaseTableName)
                WHERE
                    \(SecureVaultModels.WebsiteCredentials.Columns.id.name) = ?
                """, arguments: [accountId])

            try credentials.account.delete($0)
        }
    }

    func updateWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials, usingId id: Int64) throws {
        try db.write {

            try credentials.account.update($0)
            try $0.execute(sql: """
                UPDATE
                    \(SecureVaultModels.WebsiteCredentials.databaseTableName)
                SET
                    \(SecureVaultModels.WebsiteCredentials.Columns.password.name) = ?
                WHERE
                    \(SecureVaultModels.WebsiteCredentials.Columns.id.name) = ?

            """, arguments: [credentials.password, id])

        }
    }

    func insertWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) throws {
        try db.write {
            do {
                try credentials.account.insert($0)
                let id = $0.lastInsertedRowID
                try $0.execute(sql: """
                    INSERT INTO
                        \(SecureVaultModels.WebsiteCredentials.databaseTableName)
                    (
                        \(SecureVaultModels.WebsiteCredentials.Columns.id.name),
                        \(SecureVaultModels.WebsiteCredentials.Columns.password.name)
                    )
                    VALUES (?, ?)
                """, arguments: [id, credentials.password])
            } catch let error as DatabaseError {
                if error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
                    throw SecureVaultError.duplicateRecord
                } else {
                    throw error
                }
            }
        }
    }

    func websiteCredentialsForAccountId(_ accountId: Int64) throws -> SecureVaultModels.WebsiteCredentials? {
        return try db.read {
            guard let account = try SecureVaultModels.WebsiteAccount.fetchOne($0, key: accountId) else {
                return nil
            }

            if let result = try Row.fetchOne($0,
                                             sql: """
                SELECT
                    \(SecureVaultModels.WebsiteCredentials.Columns.password.name)
                FROM
                    \(SecureVaultModels.WebsiteCredentials.databaseTableName)
                WHERE
                    \(SecureVaultModels.WebsiteCredentials.Columns.id.name) = ?
                """, arguments: [account.id]) {

                return SecureVaultModels.WebsiteCredentials(account: account,
                                                password: result[SecureVaultModels.WebsiteCredentials.Columns.password.name])
                
            }
            return nil
        }
    }

}

// MARK: - Database Migrations

extension DefaultDatabaseProvider {

    static func migrateV1(database: Database) throws {

        try database.create(table: SecureVaultModels.WebsiteAccount.databaseTableName) {
            $0.column(SecureVaultModels.WebsiteAccount.Columns.id.name, .integer)
            $0.column(SecureVaultModels.WebsiteAccount.Columns.username.name, .text)
            $0.column(SecureVaultModels.WebsiteAccount.Columns.created.name, .date)
            $0.column(SecureVaultModels.WebsiteAccount.Columns.lastUpdated.name, .date)
            $0.primaryKey([SecureVaultModels.WebsiteAccount.Columns.id.name])
        }

        try database.create(table: SecureVaultModels.WebsiteCredentials.databaseTableName) {
            $0.column(SecureVaultModels.WebsiteCredentials.Columns.id.name, .integer)
            $0.column(SecureVaultModels.WebsiteCredentials.Columns.password.name, .blob)
            $0.primaryKey([SecureVaultModels.WebsiteCredentials.Columns.id.name])
        }

    }

    static func migrateV2(database: Database) throws {
        try database.alter(table: SecureVaultModels.WebsiteAccount.databaseTableName) {
            $0.add(column: SecureVaultModels.WebsiteAccount.Columns.domain.name, .text)
        }

        try database.create(index: SecureVaultModels.WebsiteAccount.databaseTableName + "_unique",
                            on: SecureVaultModels.WebsiteAccount.databaseTableName,
                            columns: [
                                SecureVaultModels.WebsiteAccount.Columns.domain.name,
                                SecureVaultModels.WebsiteAccount.Columns.username.name
                            ],
                            unique: true,
                            ifNotExists: true)
    }

    static func migrateV3(database: Database) throws {
        try database.alter(table: SecureVaultModels.WebsiteAccount.databaseTableName) {
            $0.add(column: SecureVaultModels.WebsiteAccount.Columns.title.name, .text)
        }
    }

}

// MARK: - Utility functions

extension DefaultDatabaseProvider {

    static internal func dbFile() throws -> URL {

        let fm = FileManager.default

#if os(macOS)
        // Note that if we move the macos browser to the app store, we should really use the alternative method
        let sandboxPathComponent = "Containers/\(Bundle.main.bundleIdentifier!)/Data/Library/Application Support/"
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let dir = libraryURL.appendingPathComponent(sandboxPathComponent)
#else
        guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not find application support directory")
        }
#endif
        let subDir = dir.appendingPathComponent("Vault")

        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: subDir.path, isDirectory: &isDir) {
            do {
                try fm.createDirectory(at: subDir, withIntermediateDirectories: true, attributes: nil)
                isDir = true
            } catch {
                fatalError("Failed to create directory at \(subDir.path)")
            }
        }

        if !isDir.boolValue {
            fatalError("Configuration folder at \(subDir.path) is not a directory")
        }

        return subDir.appendingPathComponent("Vault.db")
    }

}

// MARK: - Database records

extension SecureVaultModels.WebsiteAccount: PersistableRecord, FetchableRecord {

    enum Columns: String, ColumnExpression {
           case id, title, username, domain, created, lastUpdated
    }

    public init(row: Row) {
        id = row[Columns.id]
        title = row[Columns.title]
        username = row[Columns.username]
        domain = row[Columns.domain]
        created = row[Columns.created]
        lastUpdated = row[Columns.lastUpdated]
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.title] = title
        container[Columns.username] = username
        container[Columns.domain] = domain
        container[Columns.created] = created
        container[Columns.lastUpdated] = Date()
    }

    public static var databaseTableName: String = "website_accounts"

}

extension SecureVaultModels.WebsiteCredentials {

    enum Columns: String, ColumnExpression {
           case id, password
    }

    public static var databaseTableName: String = "website_passwords"

}
