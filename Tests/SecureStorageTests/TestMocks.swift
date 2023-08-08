//
//  MockProviders.swift
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
import SecureStorage
import GRDB

internal class MockCryptoProvider: SecureStorageCryptoProvider {

    var passwordSalt: Data {
        return Data()
    }

    var keychainServiceName: String {
        return "service"
    }

    var keychainAccountName: String {
        return "account"
    }

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
            throw SecureStorageError.invalidPassword
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

internal class MockKeyStoreProvider: SecureStorageKeyStoreProvider {

    // swiftlint:disable identifier_name
    var _l1Key: Data?
    var _encryptedL2Key: Data?
    var _generatedPassword: Data?
    var _generatedPasswordCleared = false
    var _lastEncryptedL2Key: Data?
    // swiftlint:enable identifier_name

    var generatedPasswordEntryName: String {
        return ""
    }

    var l1KeyEntryName: String {
        return ""
    }

    var l2KeyEntryName: String {
        return ""
    }

    var keychainServiceName: String {
        return ""
    }

    func attributesForEntry(named: String, serviceName: String) -> [String: Any] {
        return [:]
    }

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

protocol MockDatabaseProvider: SecureStorageDatabaseProvider {

    func storeSomeData(string: String) throws

    func getStoredData() throws -> String?

}

final class ConcreteMockDatabaseProvider: MockDatabaseProvider {

    var db: GRDB.DatabaseWriter

    init(file: URL = URL(string: "https://duckduckgo.com/")!, key: Data = Data()) throws {
        self.db = try! DatabaseQueue(named: "MockQueue")
    }

    var storedData: String?

    func storeSomeData(string: String) throws {
        self.storedData = string
    }

    func getStoredData() throws -> String? {
        return self.storedData
    }

}

protocol MockSecureVault: SecureVault {

    func storeSomeData(string: String) throws

    func getStoredData() throws -> String?

}

final class ConcreteMockSecureVault<T: MockDatabaseProvider>: MockSecureVault {

    public typealias MockStorageProviders = SecureStorageProviders<T>

    private let providers: MockStorageProviders

    public required init(providers: MockStorageProviders) {
        self.providers = providers
    }

    func storeSomeData(string: String) throws {
        try self.providers.database.storeSomeData(string: string)
    }

    func getStoredData() throws -> String? {
        return try self.providers.database.getStoredData()
    }
}

typealias MockVaultFactory = SecureVaultFactory<ConcreteMockSecureVault<ConcreteMockDatabaseProvider>>
