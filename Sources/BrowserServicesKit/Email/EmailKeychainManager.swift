//
//  EmailKeyChainManager.swift
//  DuckDuckGo
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

public class EmailKeychainManager {

    public init() {}

}

extension EmailKeychainManager: EmailManagerStorage {

    public func getUsername() throws -> String? {
        try EmailKeychainManager.getString(forField: .username)
    }
    
    public func getToken() throws -> String? {
        try EmailKeychainManager.getString(forField: .token)
    }
    
    public func getAlias() throws -> String? {
        try EmailKeychainManager.getString(forField: .alias)
    }

    public func getCohort() throws -> String? {
        try EmailKeychainManager.getString(forField: .cohort)
    }

    public func getLastUseDate() throws -> String? {
        try EmailKeychainManager.getString(forField: .lastUseDate)
    }
    
    public func store(token: String, username: String, cohort: String?) throws {
        try EmailKeychainManager.add(token: token, forUsername: username, cohort: cohort)
    }
    
    public func store(alias: String) throws {
        try EmailKeychainManager.add(alias: alias)
    }

    public func store(lastUseDate: String) throws {
        try EmailKeychainManager.add(lastUseDate: lastUseDate)
    }
    
    public func deleteAlias() {
        EmailKeychainManager.deleteItem(forField: .alias)
    }
    
    public func deleteAuthenticationState() {
        EmailKeychainManager.deleteAuthenticationState()
    }

    public func getWaitlistToken() -> String? {
        return try? EmailKeychainManager.getString(forField: .waitlistToken)
    }

    public func getWaitlistTimestamp() -> Int? {
        if let timestampResult = try? EmailKeychainManager.getString(forField: .waitlistTimestamp) {
            return Int(timestampResult)
        } else {
            return nil
        }
    }

    public func getWaitlistInviteCode() -> String? {
        return try? EmailKeychainManager.getString(forField: .inviteCode)
    }

    public func deleteWaitlistState() {
        EmailKeychainManager.deleteWaitlistState()
    }

    public func store(waitlistToken: String) {
        // Avoid saving a new token if one already exists.
        guard getWaitlistToken() == nil else { return }

        EmailKeychainManager.add(waitlistToken: waitlistToken)
    }

    public func store(waitlistTimestamp: Int) {
        // Avoid saving a new timestamp if one already exists.
        guard getWaitlistTimestamp() == nil else { return }

        let timestampString = String(waitlistTimestamp)
        EmailKeychainManager.add(waitlistTimestamp: timestampString)
    }

    public func store(inviteCode: String) {
        EmailKeychainManager.add(inviteCode: inviteCode)
    }

}

private extension EmailKeychainManager {

    /*
     Uses just kSecAttrService as the primary key, since we don't want to store
     multiple accounts/tokens at the same time
    */
    enum EmailKeychainField: String {
        case username = ".email.username"
        case token = ".email.token"
        case alias = ".email.alias"
        case lastUseDate = ".email.lastUseDate"
        case waitlistToken = ".email.waitlistToken"
        case waitlistTimestamp = ".email.waitlistTimestamp"
        case inviteCode = ".email.inviteCode"
        case cohort = ".email.cohort"
        
        var keyValue: String {
            (Bundle.main.bundleIdentifier ?? "com.duckduckgo") + rawValue
        }
    }
    
    static func getString(forField field: EmailKeychainField) throws -> String? {
        guard let data = try retrieveData(forField: field) else {
            return nil
        }
        
        if let decodedString = String(data: data, encoding: String.Encoding.utf8) {
            return decodedString
        } else {
            throw EmailKeychainAccessError.failedToDecodeKeychainDataAsString
        }
    }
    
    static func retrieveData(forField field: EmailKeychainField) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrService as String: field.keyValue,
            kSecReturnData as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess {
            if let existingItem = item as? Data {
                return existingItem
            } else {
                throw EmailKeychainAccessError.failedToDecodeKeychainValueAsData
            }
        } else if status == errSecItemNotFound {
            return nil
        } else {
            throw EmailKeychainAccessError.keychainAccessFailure(status)
        }
    }
    
    static func add(token: String, forUsername username: String, cohort: String?) throws {
        guard let tokenData = token.data(using: .utf8),
              let usernameData = username.data(using: .utf8) else {
            return
        }

        deleteAuthenticationState()
        
        try add(data: tokenData, forField: .token)
        try add(data: usernameData, forField: .username)

        if let cohortData = cohort?.data(using: .utf8) {
            try add(data: cohortData, forField: .cohort)
        }
    }
    
    static func add(alias: String) throws {
        try add(string: alias, forField: .alias)
    }

    static func add(lastUseDate: String) throws {
        try add(string: lastUseDate, forField: .lastUseDate)
    }

    static func add(waitlistToken: String) {
        try? add(string: waitlistToken, forField: .waitlistToken)
    }

    static func add(waitlistTimestamp: String) {
        try? add(string: waitlistTimestamp, forField: .waitlistTimestamp)
    }

    static func add(inviteCode: String) {
        try? add(string: inviteCode, forField: .inviteCode)
    }

    static func add(string: String, forField field: EmailKeychainField) throws {
        guard let stringData = string.data(using: .utf8) else {
            return
        }
        
        deleteItem(forField: field)
        try add(data: stringData, forField: field)
    }
    
    static func add(data: Data, forField field: EmailKeychainField) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrSynchronizable as String: false,
            kSecAttrService as String: field.keyValue,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            throw EmailKeychainAccessError.keychainAccessFailure(status)
        }
    }
    
    static func deleteAuthenticationState() {
        deleteItem(forField: .username)
        deleteItem(forField: .token)
        deleteItem(forField: .alias)
        deleteItem(forField: .cohort)
        deleteItem(forField: .lastUseDate)
    }
    
    static func deleteItem(forField field: EmailKeychainField) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: field.keyValue]
        SecItemDelete(query as CFDictionary)
    }

}

// MARK: - Debugging Extensions

public extension EmailKeychainManager {

    static func deleteInviteCode() {
        deleteItem(forField: .inviteCode)
    }

    static func deleteWaitlistState() {
        deleteItem(forField: .waitlistToken)
        deleteItem(forField: .waitlistTimestamp)
        deleteItem(forField: .inviteCode)
    }

}
