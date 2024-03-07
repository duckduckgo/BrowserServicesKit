//
//  SubscriptionCache.swift
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
import Persistence

public class SubscriptionCache {

    public enum Component: String, CustomStringConvertible, CaseIterable {
        public var description: String { rawValue }

        case entitlements
    }

    private var appGroup: String
    private lazy var userDefaults: UserDefaults? = UserDefaults(suiteName: appGroup)

    public init(appGroup: String) {
        self.appGroup = appGroup
    }

    public func set<T: Codable>(_ object: T, forKey defaultName: String) {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(object)
            userDefaults?.set(data, forKey: defaultName)
        } catch {
            assertionFailure("Failed to encode object of type \(T.self): \(error)")
        }
    }

    public func object<T: Codable>(forKey defaultName: String) -> T? {
        guard let data = userDefaults?.data(forKey: defaultName) else { return nil }
        let decoder = JSONDecoder()
        do {
            let object = try decoder.decode(T.self, from: data)
            return object
        } catch {
            assertionFailure("Failed to decode object of type \(T.self): \(error)")
            return nil
        }
    }

    public func removeObject(forKey defaultName: String) {
        userDefaults?.removeObject(forKey: defaultName)
    }

    public func cleanup() {
        for component in Component.allCases {
            removeObject(forKey: component.rawValue)
        }
    }
}
