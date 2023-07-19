//
//  SecureVault.swift
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
import Common
import GRDB

/// A vault that supports storing data at various levels.
///
/// * L0 - not encrypted.  Currently no data at this level and we're not likely to use it.
/// * L1 - secret key encrypted.  Usernames, domains, duck addresses.
/// * L2 - user password encrypted and can be accessed without password during a specifed amount of time.  User passwords.
/// * L3 - user password is required at time of request.  Currently no data at this level, but later e.g, credit cards.
///
/// Data always goes in and comes out unencrypted.
public protocol SecureVault {

    func getEncryptionKey() throws -> Data
    func encrypt(_ data: Data, using key: Data) throws -> Data
    func decrypt(_ data: Data, using key: Data) throws -> Data

    func authWith(password: Data) throws -> SecureVault
    func resetL2Password(oldPassword: Data?, newPassword: Data) throws
    func accounts() throws -> [SecureVaultModels.WebsiteAccount]
    func accountsFor(domain: String) throws -> [SecureVaultModels.WebsiteAccount]
    func accountsWithPartialMatchesFor(eTLDplus1: String) throws -> [SecureVaultModels.WebsiteAccount]
    func hasAccountFor(username: String?, domain: String?) throws -> Bool

    func websiteCredentialsFor(accountId: Int64) throws -> SecureVaultModels.WebsiteCredentials?
    @discardableResult
    func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) throws -> Int64
    func deleteWebsiteCredentialsFor(accountId: Int64) throws

    func notes() throws -> [SecureVaultModels.Note]
    func noteFor(id: Int64) throws -> SecureVaultModels.Note?
    @discardableResult
    func storeNote(_ note: SecureVaultModels.Note) throws -> Int64
    func deleteNoteFor(noteId: Int64) throws

    func identities() throws -> [SecureVaultModels.Identity]
    func identityFor(id: Int64) throws -> SecureVaultModels.Identity?
    func existingIdentityForAutofill(matching proposedIdentity: SecureVaultModels.Identity) throws -> SecureVaultModels.Identity?
    @discardableResult
    func storeIdentity(_ identity: SecureVaultModels.Identity) throws -> Int64
    func deleteIdentityFor(identityId: Int64) throws

    func creditCards() throws -> [SecureVaultModels.CreditCard]
    func creditCardFor(id: Int64) throws -> SecureVaultModels.CreditCard?
    func existingCardForAutofill(matching proposedCard: SecureVaultModels.CreditCard) throws -> SecureVaultModels.CreditCard?
    @discardableResult
    func storeCreditCard(_ card: SecureVaultModels.CreditCard) throws -> Int64
    func deleteCreditCardFor(cardId: Int64) throws

    // MARK: - Import Support

    @discardableResult
    func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials, in database: Database, encryptedUsing l2Key: Data) throws -> Int64

    // MARK: - Sync Support

    func inDatabaseTransaction(_ block: @escaping (Database) throws -> Void) throws
    func modifiedSyncableCredentials() throws -> [SecureVaultModels.SyncableCredentials]
    func deleteSyncableCredentials(_ syncableCredentials: SecureVaultModels.SyncableCredentials, in database: Database) throws
    func storeSyncableCredentials(_ syncableCredentials: SecureVaultModels.SyncableCredentials, in database: Database, encryptedUsing l2Key: Data) throws

    func syncableCredentialsForSyncIds(_ syncIds: any Sequence<String>, in database: Database) throws -> [SecureVaultModels.SyncableCredentials]
    func syncableCredentialsForAccountId(_ accountId: Int64, in database: Database) throws -> SecureVaultModels.SyncableCredentials?
}

/// Protocols can't be nested, but classes can.  This struct provides a 'namespace' for the default implementations of the providers to keep it clean for other things going on in this library.
internal struct SecureVaultProviders {

    var crypto: SecureVaultCryptoProvider
    var database: SecureVaultDatabaseProvider
    var keystore: SecureVaultKeyStoreProvider

}

class DefaultSecureVault: SecureVault {

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "Secure Vault")

    private let providers: SecureVaultProviders
    private let expiringPassword: ExpiringValue<Data>

    var authExpiry: TimeInterval {
        return expiringPassword.expiresAfter
    }

    internal init(authExpiry: TimeInterval,
                  providers: SecureVaultProviders) {
        self.providers = providers
        self.expiringPassword = ExpiringValue(expiresAfter: authExpiry)
    }

    // MARK: - public interface (protocol candidates)

    func getEncryptionKey() throws -> Data {
        let password = try passwordInUse()
        return try l2KeyFrom(password: password)
    }

    func encrypt(_ data: Data, using key: Data) throws -> Data {
        try providers.crypto.encrypt(data, withKey: key)
    }

    func decrypt(_ data: Data, using key: Data) throws -> Data {
        try providers.crypto.decrypt(data, withKey: key)
    }

    /// Sets the password which is retained for the given amount of time. Call this is you receive a `authRequired` error.
    public func authWith(password: Data) throws -> SecureVault {
        lock.lock()
        defer {
            lock.unlock()
        }

        do {
            _ = try self.l2KeyFrom(password: password) // checks the password
            self.expiringPassword.value = password
            return self
        } catch {
            let error = error as? SecureVaultError ?? .authError(cause: error)
            throw error
        }
    }

    public func resetL2Password(oldPassword: Data?, newPassword: Data) throws {
        lock.lock()
        defer {
            lock.unlock()
        }

        // Whatever happens, force a re-auth on future calls
        self.expiringPassword.value = nil

        do {
            // Use the provided old password if provided, or the stored generated password
            let generatedPassword = try self.providers.keystore.generatedPassword()
            guard let oldPassword = oldPassword ?? generatedPassword else {
                throw SecureVaultError.invalidPassword
            }

            // get decrypted l2key using old password
            let l2Key = try self.l2KeyFrom(password: oldPassword)

            // derive new encryption key
            let newEncryptionKey = try self.providers.crypto.deriveKeyFromPassword(newPassword)

            // encrypt 2 key with new encryption key and nonce
            let encryptedKey = try self.providers.crypto.encrypt(l2Key, withKey: newEncryptionKey)

            // store encrypted L2 key and nonce
            try self.providers.keystore.storeEncryptedL2Key(encryptedKey)

            // Clear the generated password now since we're def using a user provided password
            try self.providers.keystore.clearGeneratedPassword()

        } catch {

            if let error = error as? SecureVaultError {
                throw error
            } else {
                throw SecureVaultError.databaseError(cause: error)
            }

        }

    }

    public func accounts() throws -> [SecureVaultModels.WebsiteAccount] {
        lock.lock()
        defer {
            lock.unlock()
        }

        do {
            return try self.providers.database.accounts()
        } catch {
            throw SecureVaultError.databaseError(cause: error)
        }
    }

    public func accountsFor(domain: String) throws -> [SecureVaultModels.WebsiteAccount] {
        lock.lock()
        defer {
            lock.unlock()
        }

        do {
            var parts = domain.components(separatedBy: ".")
            while !parts.isEmpty {
                let accounts = try self.providers.database.websiteAccountsForDomain(parts.joined(separator: "."))
                if !accounts.isEmpty {
                    return accounts
                }
                parts.removeFirst()
            }
            return []
        } catch {
            throw SecureVaultError.databaseError(cause: error)
        }
    }

    public func accountsWithPartialMatchesFor(eTLDplus1: String) throws -> [SecureVaultModels.WebsiteAccount] {
        lock.lock()
        defer {
            lock.unlock()
        }
        do {
            return try self.providers.database.websiteAccountsForTopLevelDomain(eTLDplus1)
        } catch {
            throw SecureVaultError.databaseError(cause: error)
        }
    }

    func hasAccountFor(username: String?, domain: String?) throws -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        do {
            return try self.providers.database.hasAccountFor(username: username, domain: domain)
        } catch {
            throw SecureVaultError.databaseError(cause: error)
        }
    }

    // MARK: - Credentials

    public func websiteCredentialsFor(accountId: Int64) throws -> SecureVaultModels.WebsiteCredentials? {
        lock.lock()
        defer {
            lock.unlock()
        }

        do {
            var decryptedCredentials: SecureVaultModels.WebsiteCredentials?
            if let credentials = try self.providers.database.websiteCredentialsForAccountId(accountId) {
                if let password = credentials.password {
                    decryptedCredentials = .init(account: credentials.account,
                                                 password: try self.l2Decrypt(data: password))
                } else {
                    decryptedCredentials = credentials
                }
            }

            return decryptedCredentials
        } catch {
            let error = error as? SecureVaultError ?? SecureVaultError.databaseError(cause: error)
            throw error
        }
    }

    public func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials, in database: Database, encryptedUsing l2Key: Data) throws -> Int64 {
        let encryptedCredentials = try encryptPassword(for: credentials, using: l2Key)
        return try self.providers.database.storeWebsiteCredentials(encryptedCredentials, in: database)
    }

    public func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) throws -> Int64 {
        lock.lock()
        defer {
            lock.unlock()
        }
        do {
            let encryptedCredentials = try encryptPassword(for: credentials)
            return try self.providers.database.storeWebsiteCredentials(encryptedCredentials)
        } catch {
            let error = error as? SecureVaultError ?? SecureVaultError.databaseError(cause: error)
            throw error
        }
    }

    func storeSyncableCredentials(
        _ syncableCredentials: SecureVaultModels.SyncableCredentials,
        in database: Database,
        encryptedUsing l2Key: Data
    ) throws {
        guard let credentials = syncableCredentials.credentials else {
            assertionFailure("nil credentials passed to \(#function)")
            return
        }
        let encryptedCredentials = try encryptPassword(for: credentials, using: l2Key)
        var syncableCredentialsToStore = syncableCredentials
        syncableCredentialsToStore.credentials = encryptedCredentials
        try providers.database.storeSyncableCredentials(syncableCredentialsToStore, in: database)
    }

    private func encryptPassword(for credentials: SecureVaultModels.WebsiteCredentials, using l2Key: Data? = nil) throws -> SecureVaultModels.WebsiteCredentials {
        do {
            // Generate a new signature
            let hashData = credentials.account.hashValue + (credentials.password ?? Data())
            var creds = credentials
            creds.account.signature = try providers.crypto.hashData(hashData)
            let encryptedPassword = credentials.password == nil ? nil : try self.l2Encrypt(data: credentials.password!, using: l2Key)
            return .init(account: creds.account, password: encryptedPassword)
        } catch {
            let error = error as? SecureVaultError ?? SecureVaultError.databaseError(cause: error)
            throw error
        }
    }

    func deleteSyncableCredentials(_ syncableCredentials: SecureVaultModels.SyncableCredentials, in database: Database) throws {
        try self.providers.database.deleteSyncableCredentials(syncableCredentials, in: database)
    }

    func deleteWebsiteCredentialsFor(accountId: Int64) throws {
        try executeThrowingDatabaseOperation {
            try self.providers.database.deleteWebsiteCredentialsForAccountId(accountId)
        }
    }

    // MARK: - Notes

    func notes() throws -> [SecureVaultModels.Note] {
        return try executeThrowingDatabaseOperation {
            return try self.providers.database.notes()
        }
    }

    func noteFor(id: Int64) throws -> SecureVaultModels.Note? {
        return try executeThrowingDatabaseOperation {
            return try self.providers.database.noteForNoteId(id)
        }
    }

    func storeNote(_ note: SecureVaultModels.Note) throws -> Int64 {
        return try executeThrowingDatabaseOperation {
            return try self.providers.database.storeNote(note)
        }
    }

    func deleteNoteFor(noteId: Int64) throws {
        try executeThrowingDatabaseOperation {
            try self.providers.database.deleteNoteForNoteId(noteId)
        }
    }

    // MARK: - Identities

    func identities() throws -> [SecureVaultModels.Identity] {
        return try executeThrowingDatabaseOperation {
            return try self.providers.database.identities()
        }
    }

    func identityFor(id: Int64) throws -> SecureVaultModels.Identity? {
        return try executeThrowingDatabaseOperation {
            return try self.providers.database.identityForIdentityId(id)
        }
    }

    @discardableResult
    func storeIdentity(_ identity: SecureVaultModels.Identity) throws -> Int64 {
        return try executeThrowingDatabaseOperation {
            return try self.providers.database.storeIdentity(identity)
        }
    }

    func deleteIdentityFor(identityId: Int64) throws {
        try executeThrowingDatabaseOperation {
            try self.providers.database.deleteIdentityForIdentityId(identityId)
        }
    }
    
    func existingIdentityForAutofill(matching proposedIdentity: SecureVaultModels.Identity) throws -> SecureVaultModels.Identity? {
        let identities = try self.identities()
        
        return identities.first { existingIdentity in
            existingIdentity.hasAutofillEquality(comparedTo: proposedIdentity)
        }
    }

    // MARK: - Credit Cards

    func creditCards() throws -> [SecureVaultModels.CreditCard] {
        return try executeThrowingDatabaseOperation {
            let cards =  try self.providers.database.creditCards()
            
            let decryptedCards: [SecureVaultModels.CreditCard] = try cards.map { card in
                var mutableCard = card
                mutableCard.cardNumberData = try self.l2Decrypt(data: mutableCard.cardNumberData)
                
                return mutableCard
            }
            
            return decryptedCards
        }
    }

    func creditCardFor(id: Int64) throws -> SecureVaultModels.CreditCard? {
        return try executeThrowingDatabaseOperation {
            guard var card = try self.providers.database.creditCardForCardId(id) else {
                return nil
            }

            card.cardNumberData = try self.l2Decrypt(data: card.cardNumberData)

            return card
        }
    }
    
    func existingCardForAutofill(matching proposedCard: SecureVaultModels.CreditCard) throws -> SecureVaultModels.CreditCard? {
        let cards = try self.creditCards()
        
        return cards.first { existingCard in
            existingCard.hasAutofillEquality(comparedTo: proposedCard)
        }
    }

    @discardableResult
    func storeCreditCard(_ card: SecureVaultModels.CreditCard) throws -> Int64 {
        return try executeThrowingDatabaseOperation {
            var mutableCard = card
            
            mutableCard.cardSuffix = SecureVaultModels.CreditCard.suffix(from: mutableCard.cardNumber)
            mutableCard.cardNumberData = try self.l2Encrypt(data: mutableCard.cardNumberData)
            
            return try self.providers.database.storeCreditCard(mutableCard)
        }
    }

    func deleteCreditCardFor(cardId: Int64) throws {
        try executeThrowingDatabaseOperation {
            try self.providers.database.deleteCreditCardForCreditCardId(cardId)
        }
    }

    // MARK: - Sync Support

    func inDatabaseTransaction(_ block: @escaping (Database) throws -> Void) throws {
        try executeThrowingDatabaseOperation {
            try self.providers.database.inTransaction(block)
        }
    }

    func modifiedSyncableCredentials() throws -> [SecureVaultModels.SyncableCredentials] {
        lock.lock()
        defer {
            lock.unlock()
        }

        do {
            var syncableCredentials = try providers.database.modifiedSyncableCredentials()
            let key = try getEncryptionKey()
            for i in 0..<syncableCredentials.count {
                guard let password = syncableCredentials[i].credentials?.password else {
                    continue
                }
                syncableCredentials[i].credentials?.password = try decrypt(password, using: key)
            }

            return syncableCredentials
        } catch {
            let error = error as? SecureVaultError ?? SecureVaultError.databaseError(cause: error)
            throw error
        }
    }

    func syncableCredentialsForSyncIds(_ syncIds: any Sequence<String>, in database: Database) throws -> [SecureVaultModels.SyncableCredentials] {
        try self.providers.database.syncableCredentialsForSyncIds(syncIds, in: database)
    }

    func syncableCredentialsForAccountId(_ accountId: Int64, in database: Database) throws -> SecureVaultModels.SyncableCredentials? {
        try self.providers.database.syncableCredentialsForAccountId(accountId, in: database)
    }

    // MARK: - Private

    private func executeThrowingDatabaseOperation<DatabaseResult>(_ operation: () throws -> DatabaseResult) throws -> DatabaseResult {
        lock.lock()
        defer {
            lock.unlock()
        }

        do {
            return try operation()
        } catch {
            throw error as? SecureVaultError ?? SecureVaultError.databaseError(cause: error)
        }
    }

    private func passwordInUse() throws -> Data {
        if let generatedPassword = try providers.keystore.generatedPassword() {
            return generatedPassword
        }

        if let userPassword = expiringPassword.value {
            return userPassword
        }

        throw SecureVaultError.authRequired
    }

    private func l2KeyFrom(password: Data) throws -> Data {
        let decryptionKey = try providers.crypto.deriveKeyFromPassword(password)
        guard let encryptedL2Key = try providers.keystore.encryptedL2Key() else {
            throw SecureVaultError.noL2Key
        }
        return try providers.crypto.decrypt(encryptedL2Key, withKey: decryptionKey)
    }
    
    private func l2Encrypt(data: Data, using l2Key: Data? = nil) throws -> Data {
        let key: Data = try {
            if let l2Key {
                return l2Key
            }
            let password = try passwordInUse()
            return try l2KeyFrom(password: password)
        }()
        return try providers.crypto.encrypt(data, withKey: key)
    }

    private func l2Decrypt(data: Data, using l2Key: Data? = nil) throws -> Data {
        let key: Data = try {
            if let l2Key {
                return l2Key
            }
            let password = try passwordInUse()
            return try l2KeyFrom(password: password)
        }()
        return try providers.crypto.decrypt(data, withKey: key)
    }
}

