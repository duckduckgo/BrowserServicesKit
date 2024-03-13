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
import Common

public struct UserDefaultsCacheSettings {

    // Default expiration interval set to 24 hours
    public let defaultExpirationInterval: TimeInterval

    public init(defaultExpirationInterval: TimeInterval = 24 * 60 * 60) {
        self.defaultExpirationInterval = defaultExpirationInterval
    }
}

public enum UserDefaultsCacheKey: String {
    case subscriptionEntitlements = "com.duckduckgo.bsk.subscription.entitlements"
    case subscription = "com.duckduckgo.bsk.subscription.info"
}

/// A generic UserDefaults cache for storing and retrieving Codable objects
public class UserDefaultsCache<ObjectType: Codable> {

    private struct CacheObject: Codable {
        let expires: Date
        let object: ObjectType
    }

    private var subscriptionAppGroup: String?
    private var settings: UserDefaultsCacheSettings
    private lazy var userDefaults: UserDefaults? = {
        if let appGroup = subscriptionAppGroup {
            return UserDefaults(suiteName: appGroup)
        } else {
            return UserDefaults.standard
        }
    }()

    private let key: UserDefaultsCacheKey

    public init(subscriptionAppGroup: String? = nil, key: UserDefaultsCacheKey,
                settings: UserDefaultsCacheSettings = UserDefaultsCacheSettings()) {
        self.subscriptionAppGroup = subscriptionAppGroup
        self.key = key
        self.settings = settings
    }

    public func set(_ object: ObjectType, expires: Date = Date().addingTimeInterval(UserDefaultsCacheSettings().defaultExpirationInterval)) {
        let cacheObject = CacheObject(expires: expires, object: object)
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(cacheObject)
            userDefaults?.set(data, forKey: key.rawValue)
            os_log(.debug, log: .subscription, "Cache Set: \(cacheObject)")
        } catch {
            assertionFailure("Failed to encode CacheObject: \(error)")
        }
    }

    public func get() -> ObjectType? {
        guard let data = userDefaults?.data(forKey: key.rawValue) else { return nil }
        let decoder = JSONDecoder()
        do {
            let cacheObject = try decoder.decode(CacheObject.self, from: data)
            if cacheObject.expires > Date() {
                os_log(.debug, log: .subscription, "Cache Hit: \(ObjectType.self)")
                return cacheObject.object
            } else {
                os_log(.debug, log: .subscription, "Cache Miss: \(ObjectType.self)")
                reset()  // Clear expired data
                return nil
            }
        } catch {
            return nil
        }
    }

    public func reset() {
        os_log(.debug, log: .subscription, "Cache Clean: \(ObjectType.self)")
        userDefaults?.removeObject(forKey: key.rawValue)
    }
}
