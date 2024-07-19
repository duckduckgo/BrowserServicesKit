//
//  NetworkProtectionKeychainStore.swift
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
import Common

enum NetworkProtectionKeychainStoreError: Error, NetworkProtectionErrorConvertible {
    case failedToCastKeychainValueToData(field: String)
    case keychainReadError(field: String, status: Int32)
    case keychainWriteError(field: String, status: Int32)
    case keychainUpdateError(field: String, status: Int32)
    case keychainDeleteError(status: Int32)

    var networkProtectionError: NetworkProtectionError {
        switch self {
        case .failedToCastKeychainValueToData(let field): return .failedToCastKeychainValueToData(field: field)
        case .keychainReadError(let field, let status): return .keychainReadError(field: field, status: status)
        case .keychainWriteError(let field, let status): return .keychainWriteError(field: field, status: status)
        case .keychainUpdateError(let field, let status): return .keychainUpdateError(field: field, status: status)
        case .keychainDeleteError(let status): return .keychainDeleteError(status: status)
        }
    }
}

/// General Keychain access helper class for the NetworkProtection module. Should be used for specific KeychainStore types.
final class NetworkProtectionKeychainStore {
    private let label: String
    private let serviceName: String
    private let keychainType: KeychainType

    init(label: String,
         serviceName: String,
         keychainType: KeychainType) {

        self.label = label
        self.serviceName = serviceName
        self.keychainType = keychainType
    }

    // MARK: - Keychain Interaction

    func readData(named name: String) throws -> Data? {
        var query = defaultAttributes()
        query[kSecAttrAccount] = name
        query[kSecReturnData] = true

        var item: CFTypeRef?

        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw NetworkProtectionKeychainStoreError.failedToCastKeychainValueToData(field: name)
            }

            return data
        case errSecItemNotFound:
            return nil
        default:
            os_log("🔴 SecItemCopyMatching status %{public}@", type: .error, String(describing: status))
            throw NetworkProtectionKeychainStoreError.keychainReadError(field: name, status: status)
        }
    }

    func writeData(_ data: Data, named name: String) throws {
        var query = defaultAttributes()
        query[kSecAttrAccount] = name
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData] = data

        let status = SecItemAdd(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = updateData(data, named: name)

            if updateStatus != errSecSuccess {
                throw NetworkProtectionKeychainStoreError.keychainUpdateError(field: name, status: status)
            }
        default:
            throw NetworkProtectionKeychainStoreError.keychainWriteError(field: name, status: status)
        }
    }

    private func updateData(_ data: Data, named name: String) -> OSStatus {
        var query = defaultAttributes()
        query[kSecAttrAccount] = name

        let newAttributes = [
          kSecValueData: data,
          kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ] as [CFString: Any]

        return SecItemUpdate(query as CFDictionary, newAttributes as CFDictionary)
    }

    func deleteAll() throws {
        var query = defaultAttributes()
#if os(macOS)
        // This line causes the delete to error with status -50 on iOS. Needs investigation but, for now, just delete the first item
        // https://app.asana.com/0/1203512625915051/1205009181378521
        query[kSecMatchLimit] = kSecMatchLimitAll
#endif

        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecItemNotFound, errSecSuccess:
            break
        default:
            throw NetworkProtectionKeychainStoreError.keychainDeleteError(status: status)
        }
    }

    private func defaultAttributes() -> [CFString: Any] {
        var attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrSynchronizable: false,
            kSecAttrLabel: label,
            kSecAttrService: serviceName
        ]

        attributes.merge(keychainType.queryAttributes()) { $1 }

        return attributes
    }
}
