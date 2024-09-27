//
//  KeychainManager.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Security

public struct KeychainManager {
    /*
     Uses just kSecAttrService as the primary key, since we don't want to store
     multiple accounts/tokens at the same time
    */
    enum SubscriptionKeychainField: String, CaseIterable {
        case tokens = "subscription.v2.tokens"

        var keyValue: String {
            (Bundle.main.bundleIdentifier ?? "com.duckduckgo") + "." + rawValue
        }
    }

    func retrieveData(forField field: SubscriptionKeychainField, useDataProtectionKeychain: Bool = true) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrService as String: field.keyValue,
            kSecReturnData as String: true,
            kSecUseDataProtectionKeychain as String: useDataProtectionKeychain
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess {
            if let existingItem = item as? Data {
                return existingItem
            } else {
                throw AccountKeychainAccessError.failedToDecodeKeychainValueAsData
            }
        } else if status == errSecItemNotFound {
            return nil
        } else {
            throw AccountKeychainAccessError.keychainLookupFailure(status)
        }
    }

    func store(data: Data, forField field: SubscriptionKeychainField, useDataProtectionKeychain: Bool = true) throws {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrSynchronizable: false,
            kSecAttrService: field.keyValue,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData: data,
            kSecUseDataProtectionKeychain: useDataProtectionKeychain] as [String: Any]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            throw AccountKeychainAccessError.keychainSaveFailure(status)
        }
    }

    func deleteItem(forField field: SubscriptionKeychainField, useDataProtectionKeychain: Bool = true) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: field.keyValue,
            kSecUseDataProtectionKeychain as String: useDataProtectionKeychain]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw AccountKeychainAccessError.keychainDeleteFailure(status)
        }
    }
}
