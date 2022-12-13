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


/**
 Arbitrary User Info storage with default values. Equatable. Private extension keys do NOT intersect between extensions.
 usage:
```
 extension UserInfo.Values {

     // define keys with default values and debug description generator
     var myUserInfoString: Value<String> { .init(default: "My User Info Default Value", description: { "my value key: \($0)" }) }

     var myUserInfoBool: Value<Bool> { .init(default: false, description: { $0 ? "the flag is set" : "" }) }

 }

 let userInfo: UserInfo = [.init(\.myUserInfoString, "my value value"), .init(\.myUserInfoBool, true)]
 userInfo.myUserInfoString == "my value value"
 userInfo.myUserInfoBool = false

```
 */
@dynamicMemberLookup
public struct UserInfo: Equatable, ExpressibleByArrayLiteral {
    // structure to extend with custom Keys
    public struct Values {
        // storage struct
        public struct Value<ValueType: Equatable> {
            // stores default value for computed extension properties and actual value when added to `storage`
            public let value: ValueType

            // description generator, used the one set in the computed extension property
            let getDescription: ((ValueType) -> String)?
            public init(default value: ValueType, description: ((ValueType) -> String)? = nil) {
                self.value = value
                self.getDescription = description
            }

            public func isEqual(to other: (any UserInfoValue)?) -> Bool {
                self.value == (other as? Self)?.value
            }
            
            public var valueType: Any.Type {
                ValueType.self
            }

            public func getDescription(forValueAt keyPath: AnyKeyPath) -> String? {
                guard let keyPath = keyPath as? KeyPath<Values, Values.Value<ValueType>> else {
                    assertionFailure("Unexpected \(type(of: keyPath)), expected: \(KeyPath<Values, Values.Value<ValueType>>.self)")
                    return nil
                }
                let defaultValue = Values()[keyPath: keyPath]
                return defaultValue.getDescription?(value)
            }

        }

        fileprivate static func makeValue<T: Equatable>(from value: T, for keyPath: PartialKeyPath<Values>) -> (any UserInfoValue)? {
            guard case .some = keyPath as? KeyPath<Values, Values.Value<T>> else {
                assertionFailure("Unexpected \(type(of: keyPath)), expected: \(KeyPath<Values, Values.Value<T>>.self)")
                return nil
            }
            return Value(default: value)
        }
    }

    public struct ArrayLiteralElement {
        let key: PartialKeyPath<Values>
        let value: any Equatable
        public init<T: Equatable>(_ key: KeyPath<Values, Values.Value<T>>, _ value: T) {
            self.key = key
            self.value = value
        }
        public init<T>(key: KeyPath<Values, Values.Value<T>>, value: T) {
            self.key = key
            self.value = value
        }
    }

    private var storage = [AnyKeyPath: AnyUserInfoValue]()

    public init() {}

    public init<T: Equatable>(_ key: KeyPath<Values, Values.Value<T>>, _ value: T) {
        guard let value = Values.makeValue(from: value, for: key) else { return }
        storage = [key: value]
    }

    public init<T>(key: KeyPath<Values, Values.Value<T>>, value: T) {
        guard let value = Values.makeValue(from: value, for: key) else { return }
        storage = [key: value]
    }

    public init(arrayLiteral elements: ArrayLiteralElement...) {
        storage = elements.reduce(into: [:]) { (result, pair) in
            result[pair.key] = Values.makeValue(from: pair.value, for: pair.key)
        }
    }

    public subscript<T: Equatable>(dynamicMember keyPath: KeyPath<Values, Values.Value<T>>) -> T {
        get {
            (storage[keyPath] as? Values.Value<T>)?.value ?? Values()[keyPath: keyPath].value
        }
        set {
            storage[keyPath] = Values.Value(default: newValue)
        }
    }

    public static func == (lhs: UserInfo, rhs: UserInfo) -> Bool {
        lhs.storage.allSatisfy { (keyPath, value) in value.isEqual(to: rhs.storage[keyPath]) }
    }

    public var isEmpty: Bool {
        storage.isEmpty
    }

}

public protocol UserInfoValue {
    associatedtype ValueType: Equatable
    var valueType: Any.Type { get }
    var value: ValueType { get }
    func getDescription(forValueAt keyPath: AnyKeyPath) -> String?
    func isEqual(to other: (AnyUserInfoValue)?) -> Bool
}

extension UserInfo.Values.Value: UserInfoValue {}
public typealias AnyUserInfoValue = any UserInfoValue

extension UserInfo: CustomDebugStringConvertible {
    public var debugDescription: String {
        var result = storage.count > 1 ? "[" : ""
        for (keyPath, value) in storage {
            if !result.isEmpty {
                result.append(", ")
            }
            if let description = value.getDescription(forValueAt: keyPath) {
                result.append(description)
            } else {
                result.append("\(value.valueType): \(value.value)")
            }
        }
        if storage.count > 1 {
            result.append("]")
        }
        return result
    }
}
