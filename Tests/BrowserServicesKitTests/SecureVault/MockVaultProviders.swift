//
//  MockProviders.swift
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
@testable import BrowserServicesKit

internal class MockDatabaseProvider: SecureVaultDatabaseProvider {

    // swiftlint:disable identifier_name
    var _accounts =  [SecureVaultModels.WebsiteAccount]()
    var _forDomain = [String]()
    var _credentials: SecureVaultModels.WebsiteCredentials?
    var _lastCredentials: SecureVaultModels.WebsiteCredentials?
    // swiftlint:enable identifier_name

    func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) throws -> Int64 {
        _lastCredentials = credentials
        return _lastCredentials?.account.id ?? -1
    }

    func websiteCredentialsForAccountId(_ accountId: Int64) throws -> SecureVaultModels.WebsiteCredentials? {
        return _credentials
    }

    func websiteAccountsForDomain(_ domain: String) throws -> [SecureVaultModels.WebsiteAccount] {
        self._forDomain.append(domain)
        return _accounts
    }

    func deleteWebsiteCredentialsForAccountId(_ accountId: Int64) throws {
        self._accounts = self._accounts.filter { $0.id != accountId }
    }

    func accounts() throws -> [SecureVaultModels.WebsiteAccount] {
        return _accounts
    }

}

internal class MockCryptoProvider: SecureVaultCryptoProvider {

    // swiftlint:disable identifier_name
    var _derivedKey: Data?
    var _decryptedData: Data?
    var _lastDataToDecrypt: Data?
    var _lastDataToEncrypt: Data?
    var _lastKey: Data?
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
        return Data()
    }

    func decrypt(_ data: Data, withKey key: Data) throws -> Data {
        _lastDataToDecrypt = data
        _lastKey = key

        guard let data = _decryptedData else {
            throw SecureVaultError.invalidPassword
        }

        return data
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
