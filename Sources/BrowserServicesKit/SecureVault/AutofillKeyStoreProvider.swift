//
//  AutofillKeyStoreProvider.swift
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
import SecureStorage

final class AutofillKeyStoreProvider: SecureVaultKeyStoreProvider {

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

    var keychainServiceName: String {
        return Constants.defaultServiceName
    }

    var generatedPasswordEntryName: String {
        return EntryName.generatedPassword.rawValue
    }

    var l1KeyEntryName: String {
        return EntryName.l1Key.rawValue
    }

    var l2KeyEntryName: String {
        return EntryName.l2Key.rawValue
    }

    func readData(named name: String, serviceName: String = Constants.defaultServiceName) throws -> Data? {
        var query = attributesForEntry(named: name, serviceName: serviceName)
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
                        throw SecureStorageError.keystoreError(status: status)
                    }
                    return decodedData
                } else {
                    guard let data = item as? Data else {
                        throw SecureStorageError.keystoreError(status: status)
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
                throw SecureStorageError.keystoreError(status: status)
        }
    }

    private func migrateV1Key(name: String) throws -> Data? {
        do {
            guard let v1Key = try readData(named: name, serviceName: Constants.legacyServiceName) else {
                return nil
            }
            try writeData(v1Key, named: name, serviceName: keychainServiceName)
            return v1Key
        } catch {
            return nil
        }
    }

    // MARK: - Autofill Attributes

    func attributesForEntry(named name: String, serviceName: String) -> [String: Any] {
        if serviceName == Constants.defaultServiceName {
            return defaultAttributesForEntry(named: name)
        } else {
            return legacyAttributesForEntry(named: name)
        }
    }

    private func legacyAttributesForEntry(named name: String) -> [String: Any] {
        return [
            kSecClass: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain: true,
            kSecAttrSynchronizable: false,
            kSecAttrAccount: name
        ] as [String: Any]
    }

    private func defaultAttributesForEntry(named name: String) -> [String: Any] {
        return [
            kSecClass: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain: false,
            kSecAttrSynchronizable: false,
            kSecAttrAccount: name
        ] as [String: Any]
    }

}
