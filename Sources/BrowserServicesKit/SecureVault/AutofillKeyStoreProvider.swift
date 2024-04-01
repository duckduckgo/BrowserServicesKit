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

final class AutofillKeyStoreProvider: SecureStorageKeyStoreProvider {

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

        // `keyValue` should be used as Keychain Account names, as app variants (e.g App Store, DMG) should have separate entries
        var keyValue: String {
            (Bundle.main.bundleIdentifier ?? "com.duckduckgo") + rawValue
        }

        static func entryName(from keyValue: String) -> EntryName? {
            if keyValue == EntryName.generatedPassword.keyValue {
                return .generatedPassword
            } else if keyValue == EntryName.l1Key.keyValue {
                return .l1Key
            } else if keyValue == EntryName.l2Key.keyValue {
                return .l2Key
            }
            return nil
        }
    }

    init(keychainService: KeychainService = DefaultKeychainService()) {
        self.keychainService = keychainService
    }

    let keychainService: any KeychainService

    var keychainServiceName: String {
        return Constants.defaultServiceName
    }

    var generatedPasswordEntryName: String {
        return EntryName.generatedPassword.keyValue
    }

    var l1KeyEntryName: String {
        return EntryName.l1Key.keyValue
    }

    var l2KeyEntryName: String {
        return EntryName.l2Key.keyValue
    }

    func readData(named name: String, serviceName: String = Constants.defaultServiceName) throws -> Data? {
        var query = attributesForEntry(named: name, serviceName: serviceName)
        query[kSecReturnData as String] = true
        query[kSecAttrService as String] = serviceName

        var item: CFTypeRef?

        let status = keychainService.itemMatching(query, &item)
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

            // Look for items based on older EntryName attributes (pre-bundle-specifc Keychain storage)
            if let entryName = EntryName.entryName(from: name) {
                return try? migrateEntry(entryName: entryName, from: keychainServiceName, to: keychainServiceName)
            }

            // Look for items in pre-V2 vault
            if serviceName == Constants.defaultServiceName, let entryName = EntryName(rawValue: name) {
                return try? migrateEntry(entryName: entryName, from: Constants.legacyServiceName, to: keychainServiceName)
            }

            return nil

        default:
            throw SecureStorageError.keystoreError(status: status)
        }
    }
    
    /// Migrates an entry to new bundle-specific Keychain storage
    /// - Parameters:
    ///   - entryName: Entry to migrate. It's `rawValue` is used when reading from old storage, and it's `keyValue` is used when writing to storage
    ///   - fromService: Service name to use when querying Keychain for the entry
    ///   - toService: Service name to use when writing the value to Keychain
    /// - Returns: Optional data
    private func migrateEntry(entryName: EntryName, from fromService: String, to toService: String) throws -> Data? {
        do {
            guard let key = try readData(named: entryName.rawValue, serviceName: fromService) else {
                return nil
            }

            try writeData(key, named: entryName.keyValue, serviceName: toService)
            return key
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
