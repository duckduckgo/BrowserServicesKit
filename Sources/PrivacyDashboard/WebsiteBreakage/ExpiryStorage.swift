//
//  ExpiryStorage.swift
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
import Persistence

public typealias KeyValueStoringDictionaryRepresentable = KeyValueStoring & DictionaryRepresentable

/// A storage solution were each entry has an expiry date and a function for removing all expired entries is provided.
/// Any persistency solution implementing `KeyValueStoringDictionaryRepresentable` can be used.
public class ExpiryStorage {

    enum Keys: String {
        case expiryDatesStorage = "com.duckduckgo.UserDefaultExpiryStorage"
        case valueExpiryDate = "com.duckduckgo.UserDefaultExpiryStorage.valueExpiryDate"
        case valueData = "com.duckduckgo.UserDefaultExpiryStorage.valueData"
    }

    let localStorage: KeyValueStoringDictionaryRepresentable

    /// Default initialiser
    /// - Parameter keyValueStoring: An object managing the persistency of the key-value pairs that implements `KeyValueStoringDictionaryRepresentable`
    public init(keyValueStoring: KeyValueStoringDictionaryRepresentable) {
        self.localStorage = keyValueStoring
    }

    /// Store a value and the desired expiry date (or removes the value if nil is passed as the value) for the provided key
    /// - Parameters:
    ///   - value: The value to store, must be 
    ///   - key: The value key
    ///   - expiryDate: A date stored alongside the value, used by `removeExpiredItems(...)` for removing expired values.
    public func set(value: Any?, forKey key: String, expiryDate: Date) {

        let valueDic = [Keys.valueExpiryDate.rawValue: expiryDate, Keys.valueData.rawValue: value]
        localStorage.set(valueDic, forKey: key)
    }

    /// - Returns: The stored value assiciated to the key, nil if not existent
    public func value(forKey key: String) -> Any? {

        return entry(forKey: key)?.value
    }

    /// - Returns: The tuple expiryDate+value associated to the key, nil if they don't exist
    public func entry(forKey key: String) -> (expiryDate: Date, value: Any)? {
        guard let valueDic = localStorage.object(forKey: key) as? [String: Any],
              let expiryDate = valueDic[Keys.valueExpiryDate.rawValue] as? Date,
              let value = valueDic[Keys.valueData.rawValue]
        else {
            return nil
        }
        return (expiryDate, value)
    }

    /// Search the entire storage for values that a re a dictionary containing 2 keys: `ExpiryStorage.Keys.valueExpiryDate` and `ExpiryStorage.Keys.valueData`, if found compares the `valueExpiryDate` with the `currentDate`, if the `currentDate` > `valueExpiryDate` then the value is removed form the storage
    /// - Parameter currentDate: The date used in the comparison with the values `valueExpiryDate`
    /// - Returns: The number of values removed
    public func removeExpiredItems(currentDate: Date) -> Int {

        var removedCount = 0
        let allKeys = localStorage.dictionaryRepresentation().keys
        for key in allKeys {
            if let entry = entry(forKey: key) {
                if currentDate > entry.expiryDate {
                    localStorage.removeObject(forKey: key)
                    removedCount += 1
                }
            }
        }

        return removedCount
    }
}
