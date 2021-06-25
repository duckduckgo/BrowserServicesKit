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

    public func getUsername() -> String? {
        EmailKeychainManager.getString(forField: .username)
    }
    
    public func getToken() -> String? {
        EmailKeychainManager.getString(forField: .token)
    }
    
    public func getAlias() -> String? {
        EmailKeychainManager.getString(forField: .alias)
    }
    
    public func store(token: String, username: String) {
        EmailKeychainManager.add(token: token, forUsername: username)
    }
    
    public func store(alias: String) {
        EmailKeychainManager.add(alias: alias)
    }
    
    public func deleteAlias() {
        EmailKeychainManager.deleteItem(forField: .alias)
    }
    
    public func deleteAuthenticationState() {
        EmailKeychainManager.deleteAuthenticationState()
    }

    public func getWaitlistToken() -> String? {
        EmailKeychainManager.getString(forField: .waitlistToken)
    }

    public func getWaitlistTimestamp() -> Int? {
        guard let timestampString = EmailKeychainManager.getString(forField: .waitlistTimestamp) else { return nil }
        return Int(timestampString)
    }

    public func getWaitlistInviteCode() -> String? {
        EmailKeychainManager.getString(forField: .inviteCode)
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
        case waitlistToken = ".email.waitlistToken"
        case waitlistTimestamp = ".email.waitlistTimestamp"
        case inviteCode = ".email.inviteCode"
        
        var keyValue: String {
            (Bundle.main.bundleIdentifier ?? "com.duckduckgo") + rawValue
        }
    }
    
    static func getString(forField field: EmailKeychainField) -> String? {
        guard let data = retreiveData(forField: field),
              let string = String(data: data, encoding: String.Encoding.utf8) else {
            return nil
        }
        return string
    }
    
    static func retreiveData(forField field: EmailKeychainField) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrService as String: field.keyValue,
            kSecReturnData as String: true]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let existingItem = item as? Data else {
            return nil
        }

        return existingItem
    }
    
    static func add(token: String, forUsername username: String) {
        guard let tokenData = token.data(using: String.Encoding.utf8),
              let usernameData = username.data(using: String.Encoding.utf8) else {
            return
        }

        deleteAuthenticationState()
        
        add(data: tokenData, forField: .token)
        add(data: usernameData, forField: .username)
    }
    
    static func add(alias: String) {
        add(string: alias, forField: .alias)
    }

    static func add(waitlistToken: String) {
        add(string: waitlistToken, forField: .waitlistToken)
    }

    static func add(waitlistTimestamp: String) {
        add(string: waitlistTimestamp, forField: .waitlistTimestamp)
    }

    static func add(inviteCode: String) {
        add(string: inviteCode, forField: .inviteCode)
    }

    static func add(string: String, forField field: EmailKeychainField) {
        guard let stringData = string.data(using: .utf8) else {
            return
        }
        deleteItem(forField: field)
        add(data: stringData, forField: field)
    }
    
    static func add(data: Data, forField field: EmailKeychainField) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrSynchronizable as String: false,
            kSecAttrService as String: field.keyValue,
            kSecValueData as String: data]
        
        SecItemAdd(query as CFDictionary, nil)
    }
    
    static func deleteAuthenticationState() {
        deleteItem(forField: .username)
        deleteItem(forField: .token)
        deleteItem(forField: .alias)
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
