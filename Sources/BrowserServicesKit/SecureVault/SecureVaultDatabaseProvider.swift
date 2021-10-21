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

    @discardableResult
    func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) throws -> Int64
    func websiteCredentialsForAccountId(_ accountId: Int64) throws -> SecureVaultModels.WebsiteCredentials?
    func websiteAccountsForDomain(_ domain: String) throws -> [SecureVaultModels.WebsiteAccount]
    func deleteWebsiteCredentialsForAccountId(_ accountId: Int64) throws

    func notes() throws -> [SecureVaultModels.Note]
    func noteForNoteId(_ noteId: Int64) throws -> SecureVaultModels.Note?
    @discardableResult
    func storeNote(_ note: SecureVaultModels.Note) throws -> Int64
    func deleteNoteForNoteId(_ noteId: Int64) throws

    func identities() throws -> [SecureVaultModels.Identity]
    func identityForIdentityId(_ identityId: Int64) throws -> SecureVaultModels.Identity?
    @discardableResult
    func storeIdentity(_ identity: SecureVaultModels.Identity) throws -> Int64
    func deleteIdentityForIdentityId(_ identityId: Int64) throws

    func creditCards() throws -> [SecureVaultModels.CreditCard]
    func creditCardForCardId(_ cardId: Int64) throws -> SecureVaultModels.CreditCard?
    @discardableResult
    func storeCreditCard(_ creditCard: SecureVaultModels.CreditCard) throws -> Int64
    func deleteCreditCardForCreditCardId(_ cardId: Int64) throws

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
        migrator.registerMigration("v4", migrate: Self.migrateV4(database:))
        migrator.registerMigration("v5", migrate: Self.migrateV5(database:))
        // ... add more migrations here ...
        do {
            try migrator.migrate(db)
        } catch {
            throw error
        }
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

    @discardableResult
    func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) throws -> Int64 {

        if let id = credentials.account.id {
            try updateWebsiteCredentials(credentials, usingId: id)
            return id
        } else {
            return try insertWebsiteCredentials(credentials)
        }
    }

    func deleteWebsiteCredentialsForAccountId(_ accountId: Int64) throws {
        try db.write {
            try $0.execute(sql: """
                DELETE FROM
                    \(SecureVaultModels.WebsiteAccount.databaseTableName)
                WHERE
                    \(SecureVaultModels.WebsiteAccount.Columns.id.name) = ?
                """, arguments: [accountId])
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

    func insertWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) throws -> Int64 {
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
                return id
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

    // MARK: Notes

    func notes() throws -> [SecureVaultModels.Note] {
        return try db.read {
            return try SecureVaultModels.Note.fetchAll($0)
        }
    }

    func noteForNoteId(_ noteId: Int64) throws -> SecureVaultModels.Note? {
        try db.read {
            return try SecureVaultModels.Note.fetchOne($0, sql: """
                SELECT
                    *
                FROM
                    \(SecureVaultModels.Note.databaseTableName)
                WHERE
                    \(SecureVaultModels.Note.Columns.id.name) = ?
                """, arguments: [noteId])
        }
    }

    func storeNote(_ note: SecureVaultModels.Note) throws -> Int64 {
        if let id = note.id {
            try updateNote(note, usingId: id)
            return id
        } else {
            return try insertNote(note)
        }
    }

    func deleteNoteForNoteId(_ noteId: Int64) throws {
        try db.write {
            try $0.execute(sql: """
                DELETE FROM
                    \(SecureVaultModels.Note.databaseTableName)
                WHERE
                    \(SecureVaultModels.Note.Columns.id.name) = ?
                """, arguments: [noteId])
        }
    }

    func updateNote(_ note: SecureVaultModels.Note, usingId id: Int64) throws {
        try db.write {
            try note.update($0)
        }
    }

    func insertNote(_ note: SecureVaultModels.Note) throws -> Int64 {
        try db.write {
            try note.insert($0)
            return $0.lastInsertedRowID
        }
    }

    // MARK: Identities

    func identities() throws -> [SecureVaultModels.Identity] {
        return try db.read {
            return try SecureVaultModels.Identity.fetchAll($0)
        }
    }

    func identityForIdentityId(_ identityId: Int64) throws -> SecureVaultModels.Identity? {
        try db.read {
            return try SecureVaultModels.Identity.fetchOne($0, sql: """
                SELECT
                    *
                FROM
                    \(SecureVaultModels.Identity.databaseTableName)
                WHERE
                    \(SecureVaultModels.Identity.Columns.id.name) = ?
                """, arguments: [identityId])
        }
    }

    @discardableResult
    func storeIdentity(_ identity: SecureVaultModels.Identity) throws -> Int64 {
        if let id = identity.id {
            try updateIdentity(identity, usingId: id)
            return id
        } else {
            return try insertIdentity(identity)
        }
    }

    func deleteIdentityForIdentityId(_ identityId: Int64) throws {
        try db.write {
            try $0.execute(sql: """
                DELETE FROM
                    \(SecureVaultModels.Identity.databaseTableName)
                WHERE
                    \(SecureVaultModels.Identity.Columns.id.name) = ?
                """, arguments: [identityId])
        }
    }

    func updateIdentity(_ identity: SecureVaultModels.Identity, usingId id: Int64) throws {
        try db.write {
            try identity.update($0)
        }
    }

    func insertIdentity(_ identity: SecureVaultModels.Identity) throws -> Int64 {
        try db.write {
            try identity.insert($0)
            return $0.lastInsertedRowID
        }
    }

    // MARK: Credit Cards

    func creditCards() throws -> [SecureVaultModels.CreditCard] {
        return try db.read {
            return try SecureVaultModels.CreditCard.fetchAll($0)
        }
    }

    func creditCardForCardId(_ cardId: Int64) throws -> SecureVaultModels.CreditCard? {
        try db.read {
            return try SecureVaultModels.CreditCard.fetchOne($0, sql: """
                SELECT
                    *
                FROM
                    \(SecureVaultModels.CreditCard.databaseTableName)
                WHERE
                    \(SecureVaultModels.CreditCard.Columns.id.name) = ?
                """, arguments: [cardId])
        }
    }

    @discardableResult
    func storeCreditCard(_ creditCard: SecureVaultModels.CreditCard) throws -> Int64 {
        if let id = creditCard.id {
            try updateCreditCard(creditCard)
            return id
        } else {
            return try insertCreditCard(creditCard)
        }
    }

    func deleteCreditCardForCreditCardId(_ cardId: Int64) throws {
        try db.write {
            try $0.execute(sql: """
                DELETE FROM
                    \(SecureVaultModels.CreditCard.databaseTableName)
                WHERE
                    \(SecureVaultModels.CreditCard.Columns.id.name) = ?
                """, arguments: [cardId])
        }
    }

    func updateCreditCard(_ creditCard: SecureVaultModels.CreditCard) throws {
        try db.write {
            try creditCard.update($0)
        }
    }

    func insertCreditCard(_ creditCard: SecureVaultModels.CreditCard) throws -> Int64 {
        try db.write {
            try creditCard.insert($0)
            return $0.lastInsertedRowID
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

    static func migrateV4(database: Database) throws {
        typealias Account = SecureVaultModels.WebsiteAccount
        typealias Credentials = SecureVaultModels.WebsiteCredentials

        try database.rename(table: Account.databaseTableName,
                            to: Account.databaseTableName + "Old")
        try database.rename(table: Credentials.databaseTableName,
                            to: Credentials.databaseTableName + "Old")


        try database.create(table: Account.databaseTableName) {
            $0.autoIncrementedPrimaryKey(Account.Columns.id.name)
            $0.column(Account.Columns.username.name, .text)
            $0.column(Account.Columns.created.name, .date)
            $0.column(Account.Columns.lastUpdated.name, .date)
            $0.column(Account.Columns.domain.name, .text)
            $0.column(Account.Columns.title.name, .text)
        }

        try database.create(table: Credentials.databaseTableName) {
            $0.column(Credentials.Columns.id.name, .integer)
            $0.column(Credentials.Columns.password.name, .blob)
            $0.primaryKey([Credentials.Columns.id.name])
            $0.foreignKey([Credentials.Columns.id.name],
                          references: Account.databaseTableName, onDelete: .cascade)
        }

        try database.execute(sql: """
            INSERT INTO \(Account.databaseTableName) SELECT * FROM \(Account.databaseTableName + "Old")
            """)

        try database.execute(sql: """
            INSERT INTO \(Credentials.databaseTableName) SELECT * FROM \(Credentials.databaseTableName + "Old")
            """)

        try database.drop(table: Account.databaseTableName + "Old")
        try database.drop(table: Credentials.databaseTableName + "Old")

        try database.dropIndexIfExists(Account.databaseTableName + "_unique")

        // ifNotExists: false will throw an error if this exists already, which is ok as this shouldn't get called more than once
        try database.create(index: Account.databaseTableName + "_unique",
                            on: Account.databaseTableName,
                            columns: [
                                Account.Columns.domain.name,
                                Account.Columns.username.name
                            ],
                            unique: true,
                            ifNotExists: false)

    }

    static func migrateV5(database: Database) throws {

        try database.create(table: SecureVaultModels.Note.databaseTableName) {
            $0.autoIncrementedPrimaryKey(SecureVaultModels.Note.Columns.id.name)

            $0.column(SecureVaultModels.Note.Columns.title.name, .text)
            $0.column(SecureVaultModels.Note.Columns.created.name, .date)
            $0.column(SecureVaultModels.Note.Columns.lastUpdated.name, .date)

            $0.column(SecureVaultModels.Note.Columns.associatedDomain.name, .text)
            $0.column(SecureVaultModels.Note.Columns.text.name, .text)
        }

        try database.create(table: SecureVaultModels.Identity.databaseTableName) {
            $0.autoIncrementedPrimaryKey(SecureVaultModels.Identity.Columns.id.name)

            $0.column(SecureVaultModels.Identity.Columns.title.name, .text)
            $0.column(SecureVaultModels.Identity.Columns.created.name, .date)
            $0.column(SecureVaultModels.Identity.Columns.lastUpdated.name, .date)

            $0.column(SecureVaultModels.Identity.Columns.firstName.name, .text)
            $0.column(SecureVaultModels.Identity.Columns.middleName.name, .text)
            $0.column(SecureVaultModels.Identity.Columns.lastName.name, .text)

            $0.column(SecureVaultModels.Identity.Columns.birthdayDay.name, .integer)
            $0.column(SecureVaultModels.Identity.Columns.birthdayMonth.name, .integer)
            $0.column(SecureVaultModels.Identity.Columns.birthdayYear.name, .integer)

            $0.column(SecureVaultModels.Identity.Columns.addressStreet.name, .text)
            $0.column(SecureVaultModels.Identity.Columns.addressCity.name, .text)
            $0.column(SecureVaultModels.Identity.Columns.addressProvince.name, .text)
            $0.column(SecureVaultModels.Identity.Columns.addressPostalCode.name, .text)
            $0.column(SecureVaultModels.Identity.Columns.addressCountryCode.name, .text)

            $0.column(SecureVaultModels.Identity.Columns.homePhone.name, .text)
            $0.column(SecureVaultModels.Identity.Columns.mobilePhone.name, .text)
            $0.column(SecureVaultModels.Identity.Columns.emailAddress.name, .text)
        }

        try database.create(table: SecureVaultModels.CreditCard.databaseTableName) {
            $0.autoIncrementedPrimaryKey(SecureVaultModels.CreditCard.Columns.id.name)

            $0.column(SecureVaultModels.CreditCard.Columns.title.name, .text)
            $0.column(SecureVaultModels.CreditCard.Columns.created.name, .date)
            $0.column(SecureVaultModels.CreditCard.Columns.lastUpdated.name, .date)

            $0.column(SecureVaultModels.CreditCard.Columns.cardNumber.name, .text)
            $0.column(SecureVaultModels.CreditCard.Columns.cardholderName.name, .text)
            $0.column(SecureVaultModels.CreditCard.Columns.cardSecurityCode.name, .text)
            $0.column(SecureVaultModels.CreditCard.Columns.expirationMonth.name, .integer)
            $0.column(SecureVaultModels.CreditCard.Columns.expirationYear.name, .integer)
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

extension SecureVaultModels.CreditCard: PersistableRecord, FetchableRecord {

    enum Columns: String, ColumnExpression {
        case id, title, created, lastUpdated, cardNumber, cardholderName, cardSecurityCode, expirationMonth, expirationYear
    }

    public init(row: Row) {
        id = row[Columns.id]
        title = row[Columns.title]
        created = row[Columns.created]
        lastUpdated = row[Columns.lastUpdated]

        cardNumber = row[Columns.cardNumber]
        cardholderName = row[Columns.cardholderName]
        cardSecurityCode = row[Columns.cardSecurityCode]
        expirationMonth = row[Columns.expirationMonth]
        expirationYear = row[Columns.expirationYear]
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.title] = title
        container[Columns.created] = created
        container[Columns.lastUpdated] = Date()
        container[Columns.cardNumber] = cardNumber
        container[Columns.cardholderName] = cardholderName
        container[Columns.cardSecurityCode] = cardSecurityCode
        container[Columns.expirationMonth] = expirationMonth
        container[Columns.expirationYear] = expirationYear
    }

    public static var databaseTableName: String = "credit_cards"

}

extension SecureVaultModels.Note: PersistableRecord, FetchableRecord {

    enum Columns: String, ColumnExpression {
        case id, title, created, lastUpdated, associatedDomain, text
    }

    public init(row: Row) {
        id = row[Columns.id]
        title = row[Columns.title]
        created = row[Columns.created]
        lastUpdated = row[Columns.lastUpdated]
        associatedDomain = row[Columns.associatedDomain]
        text = row[Columns.text]
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.title] = title
        container[Columns.created] = created
        container[Columns.lastUpdated] = Date()
        container[Columns.associatedDomain] = associatedDomain
        container[Columns.text] = text
    }

    public static var databaseTableName: String = "notes"

}

extension SecureVaultModels.Identity: PersistableRecord, FetchableRecord {

    enum Columns: String, ColumnExpression {
        case id
        case title
        case created
        case lastUpdated

        case firstName
        case middleName
        case lastName

        case birthdayDay
        case birthdayMonth
        case birthdayYear

        case addressStreet
        case addressCity
        case addressProvince
        case addressPostalCode
        case addressCountryCode

        case homePhone
        case mobilePhone
        case emailAddress
    }

    public init(row: Row) {
        id = row[Columns.id]
        title = row[Columns.title]
        created = row[Columns.created]
        lastUpdated = row[Columns.lastUpdated]

        firstName = row[Columns.firstName]
        middleName = row[Columns.middleName]
        lastName = row[Columns.lastName]

        birthdayDay = row[Columns.birthdayDay]
        birthdayMonth = row[Columns.birthdayMonth]
        birthdayYear = row[Columns.birthdayYear]

        addressStreet = row[Columns.addressStreet]
        addressCity = row[Columns.addressCity]
        addressProvince = row[Columns.addressProvince]
        addressPostalCode = row[Columns.addressPostalCode]
        addressCountryCode = row[Columns.addressCountryCode]

        homePhone = row[Columns.homePhone]
        mobilePhone = row[Columns.mobilePhone]
        emailAddress = row[Columns.emailAddress]
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.title] = title
        container[Columns.created] = created
        container[Columns.lastUpdated] = Date()

        container[Columns.firstName] = firstName
        container[Columns.middleName] = middleName
        container[Columns.lastName] = lastName

        container[Columns.birthdayDay] = birthdayDay
        container[Columns.birthdayMonth] = birthdayMonth
        container[Columns.birthdayYear] = birthdayYear

        container[Columns.addressStreet] = addressStreet
        container[Columns.addressCity] = addressCity
        container[Columns.addressProvince] = addressProvince
        container[Columns.addressPostalCode] = addressPostalCode
        container[Columns.addressCountryCode] = addressCountryCode

        container[Columns.homePhone] = homePhone
        container[Columns.mobilePhone] = mobilePhone
        container[Columns.emailAddress] = emailAddress
    }

    public static var databaseTableName: String = "identities"

}
