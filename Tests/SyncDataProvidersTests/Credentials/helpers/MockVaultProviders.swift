//
//  MockVaultProviders.swift
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
import GRDB
@testable import BrowserServicesKit

internal class MockDatabaseProvider: SecureVaultDatabaseProvider {

    // swiftlint:disable identifier_name
    var _accounts = [SecureVaultModels.WebsiteAccount]()
    var _notes = [SecureVaultModels.Note]()
    var _identities = [Int64: SecureVaultModels.Identity]()
    var _creditCards = [Int64: SecureVaultModels.CreditCard]()
    var _forDomain = [String]()
    var _credentialsDict = [Int64: SecureVaultModels.WebsiteCredentials]()
    var _note: SecureVaultModels.Note?
    // swiftlint:enable identifier_name

    func hasAccountFor(username: String?, domain: String?) throws -> Bool {
        false
    }

    func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) throws -> Int64 {
        if let accountIdString = credentials.account.id, let accountID = Int64(accountIdString) {
            _credentialsDict[accountID] = credentials
            return accountID
        } else {
            _credentialsDict[-1] = credentials
            return -1
        }
    }

    func websiteCredentialsForAccountId(_ accountId: Int64) throws -> SecureVaultModels.WebsiteCredentials? {
        return _credentialsDict[accountId]
    }

    func websiteAccountsForDomain(_ domain: String) throws -> [SecureVaultModels.WebsiteAccount] {
        self._forDomain.append(domain)
        return _accounts
    }

    func websiteAccountsForTopLevelDomain(_ eTLDplus1: String) throws -> [SecureVaultModels.WebsiteAccount] {
        self._forDomain.append(eTLDplus1)
        return _accounts
    }

    func deleteWebsiteCredentialsForAccountId(_ accountId: Int64) throws {
        self._accounts = self._accounts.filter { $0.id != String(accountId) }
    }

    func accounts() throws -> [SecureVaultModels.WebsiteAccount] {
        return _accounts
    }

    func notes() throws -> [SecureVaultModels.Note] {
        return _notes
    }

    func noteForNoteId(_ noteId: Int64) throws -> SecureVaultModels.Note? {
        return _note
    }

    func deleteNoteForNoteId(_ noteId: Int64) throws {
        self._notes = self._notes.filter { $0.id != noteId }
    }

    func storeNote(_ note: SecureVaultModels.Note) throws -> Int64 {
        _note = note
        return note.id ?? -1
    }

    func identities() throws -> [SecureVaultModels.Identity] {
        return Array(_identities.values)
    }

    func identityForIdentityId(_ identityId: Int64) throws -> SecureVaultModels.Identity? {
        return _identities[identityId]
    }

    func storeIdentity(_ identity: SecureVaultModels.Identity) throws -> Int64 {
        if let identityID = identity.id {
            _identities[identityID] = identity
            return identityID
        } else {
            return -1
        }
    }

    func deleteIdentityForIdentityId(_ identityId: Int64) throws {
        _identities.removeValue(forKey: identityId)
    }

    func creditCards() throws -> [SecureVaultModels.CreditCard] {
        return Array(_creditCards.values)
    }

    func creditCardForCardId(_ cardId: Int64) throws -> SecureVaultModels.CreditCard? {
        return _creditCards[cardId]
    }

    func storeCreditCard(_ creditCard: SecureVaultModels.CreditCard) throws -> Int64 {
        if let cardID = creditCard.id {
            _creditCards[cardID] = creditCard
            return cardID
        } else {
            return -1
        }
    }

    func deleteCreditCardForCreditCardId(_ cardId: Int64) throws {
        _creditCards.removeValue(forKey: cardId)
    }

    func inTransaction(_ block: @escaping (Database) throws -> Void) throws {
    }

    func updateSyncTimestamp(in database: Database, tableName: String, objectId: Int64, timestamp: Date?) throws {
    }

    func modifiedWebsiteCredentials() throws -> [SecureVaultModels.SyncableWebsiteCredentialsInfo] {
        []
    }

    func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials, in database: Database) throws -> Int64 {
        try storeWebsiteCredentials(credentials)
    }

    func deleteWebsiteCredentialsMetadata(_ metadata: SecureVaultModels.SyncableWebsiteCredentialsInfo, in database: Database) throws {
        if let accountId = metadata.metadata.objectId {
            try deleteWebsiteCredentialsForAccountId(accountId)
        }
    }

    func websiteCredentialsMetadataForSyncIds(_ syncIds: any Sequence<String>, in database: Database) throws -> [SecureVaultModels.SyncableWebsiteCredentialsInfo] {
        []
    }

    func websiteCredentialsForAccountId(_ accountId: Int64, in database: Database) throws -> SecureVaultModels.WebsiteCredentials? {
        try websiteCredentialsForAccountId(accountId)
    }

    func websiteCredentialsMetadataForAccountId(_ accountId: Int64, in database: Database) throws -> SecureVaultModels.SyncableWebsiteCredentialsInfo? {
        nil
    }

    func websiteAccountsForDomain(_ domain: String, in database: Database) throws -> [SecureVaultModels.WebsiteAccount] {
        try websiteAccountsForDomain(domain)
    }

    func storeWebsiteCredentialsMetadata(_ metadata: SecureVaultModels.SyncableWebsiteCredentialsInfo, in database: GRDB.Database) throws {
    }

    func modifiedWebsiteCredentialsMetadata() throws -> [SecureVaultModels.SyncableWebsiteCredentialsInfo] {
        []
    }

}

internal class MockCryptoProvider: SecureVaultCryptoProvider {

    // swiftlint:disable identifier_name
    var _derivedKey: Data?
    var _decryptedData: Data?
    var _lastDataToDecrypt: Data?
    var _lastDataToEncrypt: Data?
    var _lastKey: Data?
    var hashingSalt: Data?
    // swiftlint:enable identifier_name

    func generateSecretKey() throws -> Data {
        return Data()
    }

    func generatePassword() throws -> Data {
        return Data()
    }

    func deriveKeyFromPassword(_ password: Data) throws -> Data {
        return _derivedKey!
    }

    func generateNonce() throws -> Data {
        return Data()
    }

    func encrypt(_ data: Data, withKey key: Data) throws -> Data {
        _lastDataToEncrypt = data
        _lastKey = key
        return data
    }

    func decrypt(_ data: Data, withKey key: Data) throws -> Data {
        _lastDataToDecrypt = data
        _lastKey = key

        guard let data = _decryptedData else {
            throw SecureVaultError.invalidPassword
        }

        return data
    }

    func generateSalt() throws -> Data {
        return Data()
    }

    func hashData(_ data: Data) throws -> String? {
        return ""
    }

    func hashData(_ data: Data, salt: Data?) throws -> String? {
        return ""
    }

}

internal class NoOpCryptoProvider: SecureVaultCryptoProvider {

    var hashingSalt: Data?

    func generateSecretKey() throws -> Data {
        return Data()
    }

    func generatePassword() throws -> Data {
        return Data()
    }

    func deriveKeyFromPassword(_ password: Data) throws -> Data {
        return password
    }

    func generateNonce() throws -> Data {
        return Data()
    }

    func encrypt(_ data: Data, withKey key: Data) throws -> Data {
        return data
    }

    func decrypt(_ data: Data, withKey key: Data) throws -> Data {
        return data
    }

    func generateSalt() throws -> Data {
        return Data()
    }

    func hashData(_ data: Data) throws -> String? {
        return ""
    }

    func hashData(_ data: Data, salt: Data?) throws -> String? {
        return ""
    }

}

internal class MockKeystoreProvider: SecureVaultKeyStoreProvider {

    // swiftlint:disable identifier_name
    var _l1Key: Data?
    var _encryptedL2Key: Data?
    var _generatedPassword: Data?
    var _generatedPasswordCleared = false
    var _lastEncryptedL2Key: Data?
    // swiftlint:enable identifier_name

    func storeGeneratedPassword(_ password: Data) throws {
    }

    func generatedPassword() throws -> Data? {
        return _generatedPassword
    }

    func clearGeneratedPassword() throws {
        _generatedPasswordCleared = true
    }

    func storeL1Key(_ data: Data) throws {
    }

    func l1Key() throws -> Data? {
        return _l1Key
    }

    func storeEncryptedL2Key(_ data: Data) throws {
        _lastEncryptedL2Key = data
    }

    func encryptedL2Key() throws -> Data? {
        return _encryptedL2Key
    }

}
