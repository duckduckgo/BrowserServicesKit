//
//  UserInfo.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

@dynamicMemberLookup
public struct UserInfo: Equatable {
    public struct Values {}

    private var storage = [AnyKeyPath: any Equatable]()

    public init() {}

    public subscript<T: Equatable>(dynamicMember keyPath: KeyPath<Values, T>) -> T {
        get {
            (storage[keyPath] as? T) ?? Values()[keyPath: keyPath]
        }
        set {
            storage[keyPath] = newValue
        }
    }

    public static func == (lhs: UserInfo, rhs: UserInfo) -> Bool {
        lhs.storage.allSatisfy { (keyPath, value) in value.isEqual(to: rhs.storage[keyPath]) }
    }

    public var isEmpty: Bool {
        storage.isEmpty
    }

}

public extension Equatable {
    func isEqual(to other: (any Equatable)?) -> Bool {
        self == other as? Self
    }
}

extension UserInfo: CustomDebugStringConvertible {
    public var debugDescription: String {
        var result = "["
        for (key, value) in storage {
            result.append("\(key): \(value)")
        }
        result.append("]")
        return result
    }
}
