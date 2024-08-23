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

import Common
import Foundation
import SecureStorage
import os.log

final class AutofillKeyStoreProvider: SecureStorageKeyStoreProvider {

    struct Constants {
        static let v1ServiceName = "DuckDuckGo Secure Vault"
        static let v2ServiceName = "DuckDuckGo Secure Vault v2"
        static let v3ServiceName = "DuckDuckGo Secure Vault v3"
    }

    // DO NOT CHANGE except if you want to deliberately invalidate all users's vaults.
    // The keys have a uid to deter casual hacker from easily seeing which keychain entry is related to what.
    enum EntryName: String, CaseIterable {

        case generatedPassword = "32A8C8DF-04AF-4C9D-A4C7-83096737A9C0"
        case l1Key = "79963A16-4E3A-464C-B01A-9774B3F695F1"
        case l2Key = "A5711F4D-7AA5-4F0C-9E4F-BE553F1EA299"

        // `keychainIdentifier` should be used as Keychain Account names, as app variants (e.g App Store, DMG) should have separate entries
        var keychainIdentifier: String {
            (Bundle.main.bundleIdentifier ?? "com.duckduckgo") + rawValue
        }

        var keyStoreMigrationEvent: SecureStorageKeyStoreEvent {
            switch self {
            case .l1Key:
                return .l1KeyMigration
            case .l2Key:
                return .l2KeyMigration
            case .generatedPassword:
                return .l2KeyPasswordMigration
            }
        }

        init?(_ keyValue: String) {
            switch keyValue {
            case EntryName.generatedPassword.keychainIdentifier:
                self = .generatedPassword
            case EntryName.l1Key.keychainIdentifier:
                self = .l1Key
            case EntryName.l2Key.keychainIdentifier:
                self = .l2Key
            default:
                return nil
            }
        }
    }

    let keychainService: KeychainService
    private var reporter: SecureVaultReporting?

    init(keychainService: KeychainService = DefaultKeychainService(),
         reporter: SecureVaultReporting? = nil) {
        self.keychainService = keychainService
        self.reporter = reporter
    }

    var keychainServiceName: String {
        return Constants.v3ServiceName
    }

    var generatedPasswordEntryName: String {
        return EntryName.generatedPassword.keychainIdentifier
    }

    var l1KeyEntryName: String {
        return EntryName.l1Key.keychainIdentifier
    }

    var l2KeyEntryName: String {
        return EntryName.l2Key.keychainIdentifier
    }

    func readData(named name: String, serviceName: String) throws -> Data? {
        try readOrMigrate(named: name, serviceName: serviceName)
    }

    /// Attempts to read data using default query, and if not found attempts to find data using older queries and migrate it using latest storage attributes
    /// - Parameters:
    ///   - name: Query account name
    ///   - serviceName: Query service name
    /// - Returns: Optional data
    private func readOrMigrate(named name: String, serviceName: String) throws -> Data? {
        if let data = try read(named: name, serviceName: serviceName) {
            Logger.autofill.debug("Autofill Keystore data retrieved")
            return data
        } else {
            guard let entryName = EntryName(name) else { return nil }

            reporter?.secureVaultKeyStoreEvent(entryName.keyStoreMigrationEvent)

            // Look for items in V2 vault (i.e pre-bundle-specifc Keychain storage)
            if let data = try migrateEntry(entryName: entryName, serviceName: Constants.v2ServiceName) {
                Logger.autofill.debug("Migrated V2 Autofill Keystore data")
                return data
            // Look for items in V1 vault
            } else if let data = try migrateEntry(entryName: entryName, serviceName: Constants.v1ServiceName) {
                Logger.autofill.debug("Migrated V1 Autofill Keystore data")
                return data
            }

            return nil
        }
    }

    /// Attempts to read data using default query, and if not found, returns nil
    /// - Parameters:
    ///   - name: Query account name
    ///   - serviceName: Query service name
    /// - Returns: Optional data
    private func read(named name: String, serviceName: String) throws -> Data? {
        var query = attributesForEntry(named: name, serviceName: serviceName)
        query[kSecReturnData as String] = true
        query[kSecAttrService as String] = serviceName

        var item: CFTypeRef?

        let status = keychainService.itemMatching(query, &item)
        switch status {
        case errSecSuccess:
            if isPostV1(serviceName) {
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
            return nil
        default:
            throw SecureStorageError.keystoreError(status: status)
        }
    }

    /// Migrates an entry to new bundle-specific Keychain storage
    /// - Parameters:
    ///   - entryName: Entry to migrate. It's `rawValue` is used when reading from old storage, and it's `keyValue` is used when writing to storage
    ///   - serviceName: Service name to use when querying Keychain for the entry
    /// - Returns: Optional data
    private func migrateEntry(entryName: EntryName, serviceName: String) throws -> Data? {
        guard let data = try read(named: entryName.rawValue, serviceName: serviceName) else {
            return nil
        }
        try writeData(data, named: entryName.keychainIdentifier, serviceName: keychainServiceName)
        return data
    }

    private func isPostV1(_ serviceName: String) -> Bool {
        [Constants.v2ServiceName, Constants.v3ServiceName].contains(serviceName)
    }

    // MARK: - Autofill Attributes

    func attributesForEntry(named name: String, serviceName: String) -> [String: Any] {
        if isPostV1(serviceName) {
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
