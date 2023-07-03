//
//  SecureVaultKeyStoreProvider.swift
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

protocol SecureVaultKeyStoreProvider {

    func storeGeneratedPassword(_ password: Data) throws
    func generatedPassword() throws -> Data?
    func clearGeneratedPassword() throws

    func storeL1Key(_ data: Data) throws
    func l1Key() throws -> Data?

    func storeEncryptedL2Key(_ data: Data) throws
    func encryptedL2Key() throws -> Data?

}

final class DefaultKeyStoreProvider: SecureVaultKeyStoreProvider {

    struct Constants {
        static let legacyServiceName = "DuckDuckGo Secure Vault"
        static let defaultServiceName = "DuckDuckGo Secure Vault v2"
    }

    // DO NOT CHANGE except if you want to deliberately invalidate all users's vaults.
    // The keys have a uid to deter casual hacker from easily seeing which keychain entry is related to what.
    private enum EntryName: String {

        case generatedPassword = "32A8C8DF-04AF-4C9D-A4C7-83096737A9C0"
        case l1Key = "79963A16-4E3A-464C-B01A-9774B3F695F1"
        case l2Key = "A5711F4D-7AA5-4F0C-9E4F-BE553F1EA299"

    }

    func generatedPassword() throws -> Data? {
        return try readData(named: .generatedPassword)
    }

    func clearGeneratedPassword() throws {
        try deleteEntry(named: .generatedPassword)
    }

    func storeGeneratedPassword(_ password: Data) throws {
        try writeData(password, named: .generatedPassword)
    }

    func storeL1Key(_ data: Data) throws {
        try writeData(data, named: .l1Key)
    }

    func storeEncryptedL2Key(_ data: Data) throws {
        try writeData(data, named: .l2Key)
    }

    func l1Key() throws -> Data? {
        return try readData(named: .l1Key)
    }

    func encryptedL2Key() throws -> Data? {
        return try readData(named: .l2Key)
    }

    private func readData(named name: EntryName, serviceName: String = Constants.defaultServiceName) throws -> Data? {
        var query = (serviceName == Constants.defaultServiceName) ? defaultAttributesForEntry(named: name) : legacyAttributesForEntry(named: name)
        query[kSecReturnData as String] = true
        query[kSecAttrService as String] = serviceName

        var item: CFTypeRef?

        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
            case errSecSuccess:
                if serviceName == Constants.defaultServiceName {
                    guard let itemData = item as? Data,
                          let itemString = String(data: itemData, encoding: .utf8),
                          let decodedData = Data(base64Encoded: itemString) else {
                        throw SecureVaultError.keystoreError(status: status)
                    }
                    return decodedData
                } else {
                    guard let data = item as? Data else {
                        throw SecureVaultError.keystoreError(status: status)
                    }
                    return data
                }

            case errSecItemNotFound:

                // Look for an older key and try to migrate
                if serviceName == Constants.defaultServiceName {
                    return try? migrateV1Key(name: name)
                }
                return nil

            default:
                throw SecureVaultError.keystoreError(status: status)
        }
    }

    private func migrateV1Key(name: EntryName) throws -> Data? {
        do {
            guard let v1Key = try readData(named: name, serviceName: Constants.legacyServiceName) else {
                return nil
            }
            try writeData(v1Key, named: name)
            return v1Key
        } catch {
            return nil
        }
    }

    private func writeData(_ data: Data, named name: EntryName, serviceName: String = Constants.defaultServiceName) throws {
        let base64String = data.base64EncodedString()

        guard let base64Data = base64String.data(using: .utf8) else {
            throw SecureVaultError.encodingFailed
        }

        var query = defaultAttributesForEntry(named: name)
        query[kSecAttrService as String] = serviceName
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        query[kSecValueData as String] = base64Data

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw SecureVaultError.keystoreError(status: status)
        }
    }

    private func deleteEntry(named name: EntryName) throws {
        let query = defaultAttributesForEntry(named: name)

        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecItemNotFound, errSecSuccess: break
        default:
            throw SecureVaultError.keystoreError(status: status)
        }
    }

    private func legacyAttributesForEntry(named name: EntryName) -> [String: Any] {
        return [
            kSecClass: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain: true,
            kSecAttrSynchronizable: false,
            kSecAttrAccount: name.rawValue
        ] as [String: Any]
    }

    private func defaultAttributesForEntry(named name: EntryName) -> [String: Any] {
        return [
            kSecClass: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain: false,
            kSecAttrSynchronizable: false,
            kSecAttrAccount: name.rawValue
        ] as [String: Any]
    }

}
