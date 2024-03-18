//
//  GenericKeychainStorage.swift
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

public enum GenericKeychainStorageAccessError: Error {
    case failedToDecodeKeychainValueAsData(GenericKeychainStorageFieldName)
    case failedToDecodeKeychainDataAsString(GenericKeychainStorageFieldName)
    case failedToEncodeDataAsString(GenericKeychainStorageFieldName)
    case keychainSaveFailure(GenericKeychainStorageFieldName, OSStatus)
    case keychainUpdateFailure(GenericKeychainStorageFieldName, OSStatus)
    case keychainDeleteFailure(GenericKeychainStorageFieldName, OSStatus)
    case keychainLookupFailure(GenericKeychainStorageFieldName, OSStatus)

    public var errorDescription: String {
        switch self {
        case .failedToDecodeKeychainValueAsData(let fieldName):
            return "failedToDecodeKeychainValueAsData(\(fieldName))"
        case .failedToDecodeKeychainDataAsString(let fieldName):
            return "failedToDecodeKeychainDataAsString(\(fieldName))"
        case .failedToEncodeDataAsString(let fieldName):
            return "failedToEncodeDataAsString(\(fieldName))"
        case .keychainSaveFailure(let fieldName, let statusCode):
            return "keychainSaveFailure(\(fieldName),\(statusCode))"
        case .keychainUpdateFailure(let fieldName, let statusCode):
            return "keychainUpdateFailure(\(fieldName),\(statusCode))"
        case .keychainDeleteFailure(let fieldName, let statusCode):
            return "keychainDeleteFailure(\(fieldName),\(statusCode))"
        case .keychainLookupFailure(let fieldName, let statusCode):
            return "keychainLookupFailure(\(fieldName),\(statusCode))"
        }
    }
}

public typealias GenericKeychainStorageFieldName = String

protocol GenericKeychainStorageField where Self: RawRepresentable, RawValue == String {
    var keyValue: String { get }
}

public class GenericKeychainStorage {

    public weak var delegate: GenericKeychainStorageErrorDelegate?

    private let keychainType: KeychainType

    public init(keychainType: KeychainType = .dataProtection(.unspecified)) {
        self.keychainType = keychainType
    }

    func getString(forField field: any GenericKeychainStorageField) -> String? {
        let data: Data?

        do {
            data = try retrieveData(forField: field)
        } catch {
            if let error = error as? GenericKeychainStorageAccessError {
                delegate?.keychainAccessFailed(error: error)
            } else {
                assertionFailure("Expected GenericKeychainStorageAccessError")
            }

            return nil
        }

        if data == nil {
            return nil
        } else if let data, let decodedString = String(data: data, encoding: String.Encoding.utf8) {
            return decodedString
        } else {
            delegate?.keychainAccessFailed(error: GenericKeychainStorageAccessError.failedToDecodeKeychainDataAsString(field.rawValue))
            return nil
        }
    }

    private func retrieveData(forField field: any GenericKeychainStorageField) throws -> Data? {
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
                throw GenericKeychainStorageAccessError.failedToDecodeKeychainValueAsData(field.rawValue)
            }
        } else if status == errSecItemNotFound {
            return nil
        } else {
            throw GenericKeychainStorageAccessError.keychainLookupFailure(field.rawValue, status)
        }
    }

    func set(string: String, forField field: any GenericKeychainStorageField) {
        guard let stringData = string.data(using: .utf8) else {
            delegate?.keychainAccessFailed(error: GenericKeychainStorageAccessError.failedToEncodeDataAsString(field.rawValue))
            return
        }

        do {
            try store(data: stringData, forField: field)
        } catch  {
            if let error = error as? GenericKeychainStorageAccessError {
                delegate?.keychainAccessFailed(error: error)
            } else {
                assertionFailure("Expected GenericKeychainStorageAccessError")
            }
        }
    }

    func store(data: Data, forField field: any GenericKeychainStorageField) throws {
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
                throw GenericKeychainStorageAccessError.keychainUpdateFailure(field.rawValue, status)
            }
        default:
            throw GenericKeychainStorageAccessError.keychainSaveFailure(field.rawValue, status)
        }
    }

    private func updateData(_ data: Data, forField field: any GenericKeychainStorageField) -> OSStatus {
        var query = defaultAttributes()
        query[kSecAttrService] = field.keyValue

        let newAttributes = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ] as [CFString: Any]

        return SecItemUpdate(query as CFDictionary, newAttributes as CFDictionary)
    }

    func deleteItem(forField field: any GenericKeychainStorageField) {
        let query = defaultAttributes()

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            delegate?.keychainAccessFailed(error: GenericKeychainStorageAccessError.keychainDeleteFailure(field.rawValue, status))
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

public enum KeychainType {
    case dataProtection(_ accessGroup: AccessGroup)
    case system
    case fileBased

    public enum AccessGroup {
        case unspecified
        case named(_ name: String)
    }

    func queryAttributes() -> [CFString: Any] {
        switch self {
        case .dataProtection(let accessGroup):
            switch accessGroup {
            case .unspecified:
                return [kSecUseDataProtectionKeychain: true]
            case .named(let accessGroup):
                return [
                    kSecUseDataProtectionKeychain: true,
                    kSecAttrAccessGroup: accessGroup
                ]
            }
        case .system:
            return [kSecUseDataProtectionKeychain: false]
        case .fileBased:
            return [kSecUseDataProtectionKeychain: false]
        }
    }
}

public protocol GenericKeychainStorageErrorDelegate: AnyObject {
    func keychainAccessFailed(error: GenericKeychainStorageAccessError)
}
