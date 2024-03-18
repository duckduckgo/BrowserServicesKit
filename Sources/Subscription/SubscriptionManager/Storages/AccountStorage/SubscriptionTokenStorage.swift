//
//  SubscriptionTokenStorage.swift
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

public protocol SubscriptionTokenStorage: AnyObject {
    func getAccessToken() throws -> String?
    func store(accessToken: String) throws
    func removeAccessToken() throws
}

public class SubscriptionTokenKeychainStorage: GenericKeychainStorage, SubscriptionTokenStorage {

    enum AccountKeychainField: String, GenericKeychainStorageField {
        case accessToken = "subscription.account.accessToken"
        case testString = "subscription.account.testString"

        var keyValue: String {
            "com.duckduckgo" + "." + rawValue
        }
    }

    override public init(keychainType: KeychainType) {
        super.init(keychainType: keychainType)
    }

    public func getAccessToken() throws -> String? {
        try getString(forField: AccountKeychainField.accessToken)
    }

    public func store(accessToken: String) throws {
        try set(string: accessToken, forField: AccountKeychainField.accessToken)
    }

    public func removeAccessToken() throws {
        try deleteItem(forField: AccountKeychainField.accessToken)
    }
}
