//
//  SubscriptionTokenKeychainStorageV2.swift
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
import os.log
import Networking
import Common

public final class SubscriptionTokenKeychainStorageV2: TokenStoring {

    private let keychainType: KeychainType
    internal let queue = DispatchQueue(label: "SubscriptionTokenKeychainStorageV2.queue")

    public init(keychainType: KeychainType = .dataProtection(.unspecified)) {
        self.keychainType = keychainType
    }

    public var tokenContainer: TokenContainer? {
        get {
            queue.sync {
                Logger.subscriptionKeychain.debug("Retrieving TokenContainer")
                guard let data = try? retrieveData(forField: .tokens) else {
                    Logger.subscriptionKeychain.debug("TokenContainer not found")
                    return nil
                }
                return CodableHelper.decode(jsonData: data)
            }
        }
        set {
            queue.sync { [weak self] in
                Logger.subscriptionKeychain.debug("Setting TokenContainer")
                guard let strongSelf = self else { return }

                do {
                    guard let newValue else {
                        Logger.subscriptionKeychain.debug("Removing TokenContainer")
                        try strongSelf.deleteItem(forField: .tokens)
                        return
                    }

                    if let data = CodableHelper.encode(newValue) {
                        try strongSelf.store(data: data, forField: .tokens)
                    } else {
                        Logger.subscriptionKeychain.fault("Failed to encode TokenContainer")
                        assertionFailure("Failed to encode TokenContainer")
                    }
                } catch {
                    Logger.subscriptionKeychain.fault("Failed to set TokenContainer: \(error, privacy: .public)")
                    assertionFailure("Failed to set TokenContainer")
                }
            }
        }
    }
}

extension SubscriptionTokenKeychainStorageV2 {

    /*
     Uses just kSecAttrService as the primary key, since we don't want to store
     multiple accounts/tokens at the same time
     */
    enum SubscriptionKeychainField: String, CaseIterable {
        case tokens = "subscription.v2.tokens"

        var keyValue: String {
            "com.duckduckgo" + "." + rawValue
        }
    }

    func getString(forField field: SubscriptionKeychainField) throws -> String? {
        guard let data = try retrieveData(forField: field) else {
            return nil
        }

        if let decodedString = String(data: data, encoding: String.Encoding.utf8) {
            return decodedString
        } else {
            throw AccountKeychainAccessError.failedToDecodeKeychainDataAsString
        }
    }

    func retrieveData(forField field: SubscriptionKeychainField) throws -> Data? {
        var query = defaultAttributes()
        query[kSecAttrService] = field.keyValue
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true

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

    func set(string: String, forField field: SubscriptionKeychainField) throws {
        guard let stringData = string.data(using: .utf8) else {
            return
        }

        try store(data: stringData, forField: field)
    }

    func store(data: Data, forField field: SubscriptionKeychainField) throws {
        var query = defaultAttributes()
        query[kSecAttrService] = field.keyValue
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData] = data

        let status = SecItemAdd(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = updateData(data, forField: field)

            if updateStatus != errSecSuccess {
                throw AccountKeychainAccessError.keychainSaveFailure(status)
            }
        default:
            throw AccountKeychainAccessError.keychainSaveFailure(status)
        }
    }

    private func updateData(_ data: Data, forField field: SubscriptionKeychainField) -> OSStatus {
        var query = defaultAttributes()
        query[kSecAttrService] = field.keyValue

        let newAttributes = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ] as [CFString: Any]

        return SecItemUpdate(query as CFDictionary, newAttributes as CFDictionary)
    }

    func deleteItem(forField field: SubscriptionKeychainField, useDataProtectionKeychain: Bool = true) throws {
        let query = defaultAttributes()

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw AccountKeychainAccessError.keychainDeleteFailure(status)
        }
    }

    private func defaultAttributes() -> [CFString: Any] {
        var attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrSynchronizable: false
        ]
        attributes.merge(keychainType.queryAttributes()) { $1 }
        return attributes
    }
}
