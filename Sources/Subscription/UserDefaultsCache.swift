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

public enum UserDefaultsCacheKey: String {
    case subscriptionEntitlements = "com.duckduckgo.bsk.subscription.entitlements"
    case subscription = "com.duckduckgo.bsk.subscription.info"
}

/// A generic UserDefaults cache for storing and retrieving Codable objects.
public class UserDefaultsCache<ObjectType: Codable> {
    private var subscriptionAppGroup: String?
    private lazy var userDefaults: UserDefaults? = {
        if let appGroup = subscriptionAppGroup {
            return UserDefaults(suiteName: appGroup)
        } else {
            return UserDefaults.standard
        }
    }()
    private let key: UserDefaultsCacheKey

    public init(subscriptionAppGroup: String? = nil, key: UserDefaultsCacheKey) {
        self.subscriptionAppGroup = subscriptionAppGroup
        self.key = key
    }

    public func set(_ object: ObjectType) {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(object)
            userDefaults?.set(data, forKey: key.rawValue)
        } catch {
            assertionFailure("Failed to encode object of type \(ObjectType.self): \(error)")
        }
    }

    public func get() -> ObjectType? {
        guard let data = userDefaults?.data(forKey: key.rawValue) else { return nil }
        let decoder = JSONDecoder()
        do {
            let object = try decoder.decode(ObjectType.self, from: data)
            return object
        } catch {
            assertionFailure("Failed to decode object of type \(ObjectType.self): \(error)")
            return nil
        }
    }

    public func reset() {
        userDefaults?.removeObject(forKey: key.rawValue)
    }
}
