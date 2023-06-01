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

final class D: SecureVaultKeyStoreProvider {

    struct Constants {
        static let defaultServiceName = "DuckDuckGo Secure Vault"
    }

    // DO NOT CHANGE except if you want to deliberately invalidate all users's vaults.
    // The keys have a uid to deter casual hacker from easily seeing which keychain entry is related to what.
    private enum EntryName: String {

        case generatedPassword = "32A8C8DF-04AF-4C9D-A4C7-83096737A9C0"
        case l1Key = "79963A16-4E3A-464C-B01A-9774B3F695F1"
        case l2Key = "A5711F4D-7AA5-4F0C-9E4F-BE553F1EA299"

    }

    let serviceName: String

    init(serviceName: String = Constants.defaultServiceName) {
        self.serviceName = serviceName
    }

    func generatedPassword() throws -> Data? {
        return try readData(named: .generatedPassword)
    }

    func clearGeneratedPassword() throws {
        try deleteEntry(named: .generatedPassword)
    }

    func clearL1Key() throws {
        try deleteEntry(named: .l1Key)
    }

    func clearL2Key() throws {
        try deleteEntry(named: .l2Key)
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

    private func readData(named name: EntryName) throws -> Data? {
        var query = defaultAttributesForEntry(named: name)
        query[kSecReturnData as String] = true

        var item: CFTypeRef?

        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw SecureVaultError.keystoreError(status: status)
            }

//            if name == .l1Key && !UserDefaults.shared.bool(forKey: "l1keyUpdated") {
//                writeData(data, named: name)
//                UserDefaults.standard.set(true, forKey: "l1keyUpdated")
//            }
//
//            if name == .l2Key && !UserDefaults.shared.bool(forKey: "l2keyUpdated") {
//                writeData(data, named: name)
//                UserDefaults.standard.set(true, forKey: "l2keyUpdated")
//            }
//
//            if name == .generatedPassword && !UserDefaults.shared.bool(forKey: "generatedPasswordUpdated") {
//                writeData(data, named: name)
//                UserDefaults.standard.set(true, forKey: "generatedPasswordUpdated")
//            }
            

            return data
        case errSecItemNotFound:
            return nil
        default:
            throw SecureVaultError.keystoreError(status: status)
        }
    }

    private func writeData(_ data: Data, named name: EntryName) throws {
        var attributes: [String: Any] = [
             kSecClass as String: kSecClassGenericPassword,
             kSecAttrAccount as String: name.rawValue,
             kSecValueData as String: data,
             kSecAttrService as String: Constants.defaultServiceName,
             kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
         ]

        let status = SecItemAdd(attributes as CFDictionary, nil)

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

    private func defaultAttributesForEntry(named name: EntryName) -> [String: Any] {
        return [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: name.rawValue
        ] as [String: Any]
    }

}
