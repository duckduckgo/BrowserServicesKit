//
//  UserDefaultsCache.swift
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

public struct UserDefaultsCacheSettings {
    public let defaultExpirationInterval: TimeInterval

    public init(defaultExpirationInterval: TimeInterval) {
        self.defaultExpirationInterval = defaultExpirationInterval
    }
}

public protocol UserDefaultsCacheKeyStore {
    var rawValue: String { get }
}

public enum UserDefaultsCacheKey: String, UserDefaultsCacheKeyStore {
    case subscriptionEntitlements = "com.duckduckgo.bsk.subscription.entitlements"
    case subscription = "com.duckduckgo.bsk.subscription.info"
}

/// A generic UserDefaults cache for storing and retrieving Codable objects
public class UserDefaultsCache<ObjectType: Codable> {

    private struct CacheObject: Codable {
        let expires: Date
        let object: ObjectType
    }

    private var userDefaults: UserDefaults
    public private(set) var settings: UserDefaultsCacheSettings

    private let key: UserDefaultsCacheKeyStore

    public init(userDefaults: UserDefaults = UserDefaults.standard,
                key: UserDefaultsCacheKeyStore,
                settings: UserDefaultsCacheSettings) {
        self.key = key
        self.settings = settings
        self.userDefaults = userDefaults
    }

    public func set(_ object: ObjectType, expires: Date? = nil) {
        let expiryDate = expires ?? Date().addingTimeInterval(self.settings.defaultExpirationInterval)
        let cacheObject = CacheObject(expires: expiryDate, object: object)
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(cacheObject)
            userDefaults.set(data, forKey: key.rawValue)
            os_log(.debug, log: .general, "Cache Set: \(cacheObject)")
        } catch {
            assertionFailure("Failed to encode CacheObject: \(error)")
        }
    }

    public func get() -> ObjectType? {
        guard let data = userDefaults.data(forKey: key.rawValue) else { return nil }
        let decoder = JSONDecoder()
        do {
            let cacheObject = try decoder.decode(CacheObject.self, from: data)
            if cacheObject.expires > Date() {
                os_log(.debug, log: .general, "Cache Hit: \(ObjectType.self)")
                return cacheObject.object
            } else {
                os_log(.debug, log: .general, "Cache Miss: \(ObjectType.self)")
                reset()  // Clear expired data
                return nil
            }
        } catch let error {
            os_log(.error, log: .general, "Cache Decode Error: \(error)")
            return nil
        }
    }

    public func reset() {
        os_log(.debug, log: .general, "Cache Clean: \(ObjectType.self)")
        userDefaults.removeObject(forKey: key.rawValue)
    }
}
