//
//  SubscriptionAccountStorage.swift
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

public protocol SubscriptionAccountStorage: AnyObject {
    var email: String? { get set }
    var externalID: String? { get set }
    func clear()
}

public class SubscriptionAccountKeychainStorage: GenericKeychainStorage, SubscriptionAccountStorage {

    enum SubscriptionAccountKeychainField: String, GenericKeychainStorageField, CaseIterable {
        case email = "subscription.account.email"
        case externalID = "subscription.account.externalID"

        var keyValue: String {
            "com.duckduckgo" + "." + rawValue
        }
    }

    override public init(keychainType: KeychainType) {
        super.init(keychainType: keychainType)
    }

    @GenericKeychainStorageFieldAccessors(field: SubscriptionAccountKeychainField.email)
    public var email: String?

    @GenericKeychainStorageFieldAccessors(field: SubscriptionAccountKeychainField.externalID)
    public var externalID: String?

    public func clear() {
        SubscriptionAccountKeychainField.allCases.forEach { deleteItem(forField: $0) }
    }
}
