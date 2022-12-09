//
//  DebugTools.swift
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

public protocol DebugValueProtocol {
    static var _defaultValue: Self { get }
}
extension Optional: DebugValueProtocol {
    public static var _defaultValue: Optional<Wrapped> { .none }
}
extension Bool: DebugValueProtocol {
    public static var _defaultValue: Bool { false }
}
extension Int: DebugValueProtocol {
    public static var _defaultValue: Int { 0 }
}
extension UInt64: DebugValueProtocol {
    public static var _defaultValue: UInt64 { 0 }
}
extension String: DebugValueProtocol {
    public static var _defaultValue: String { "" }
}
extension Array: DebugValueProtocol {
    public static var _defaultValue: Array { [] }
}
extension Dictionary {
    public static var _defaultValue: Dictionary { [:] }
}

public struct Debug {
    private init() {}

    @propertyWrapper
    public struct Value<T>: Hashable where T: DebugValueProtocol {
#if DEBUG
        public var wrappedValue: T = ._defaultValue
        public init(wrappedValue: T) {
            self.wrappedValue = wrappedValue
        }
#else
        public var wrappedValue: T {
            get { ._defaultValue }
            set {}
        }
        public init(wrappedValue: @autoclosure () -> T) {}
#endif
        public init() {}

        public static func == (lhs: Debug.Value<T>, rhs: Debug.Value<T>) -> Bool { true }
        public func hash(into hasher: inout Hasher) {}
    }

    public static func expectDeallocation(of object: AnyObject?) {
        if object == nil { return }
        async(on: .main, after: .now() + 0.1) {  [weak object] in
            assert(object == nil)
        }
    }

#if DEBUG

    public static func run(_ block: () -> ()) {
        block()
    }
    public static func eval<T: DebugValueProtocol>(_ block: () -> T) -> T {
        block()
    }

    public static func checkMainThread() {
        assert(Thread.isMainThread)
    }

    public static func async(on queue: DispatchQueue, _ work: @escaping @convention(block) () -> Void) {
        queue.async(execute: work)
    }

    public static func async(on queue: DispatchQueue, after deadline: DispatchTime, _ work: @escaping @convention(block) () -> Void) {
        queue.asyncAfter(deadline: deadline, execute: work)
    }

#else

    public static func async(on queue: DispatchQueue, _ work: () -> Void) {}
    public static func async(on queue: DispatchQueue, _ work: @convention(block) () -> Void) {}

    public static func run(_: () -> ()) {}
    public static func eval<T: DebugValueProtocol>(_: () -> T) -> T {}

    public static func checkMainThread() {}

    public static func expectDeallocation(of object: @autoclosure () -> AnyObject?) {}

#endif
}
