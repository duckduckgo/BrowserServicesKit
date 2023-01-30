//
//  ResponderChain.swift
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

public struct ResponderChain<Responder> {

    private var responderRefs: [ResponderRef<Responder>]

    public init(responderRefs: [ResponderRef<Responder>] = []) {
        self.responderRefs = responderRefs
    }

    public mutating func setResponders(_ refs: [ResponderRefMaker<Responder>]) {
        dispatchPrecondition(condition: .onQueue(.main))

        let nonnullRefs = refs.compactMap { $0 }
        responderRefs = nonnullRefs.map(\.ref)
        assert(getResponders().count == nonnullRefs.count, "Some NavigationResponders were released right after adding: "
               + "\(Set(nonnullRefs.map(\.ref.responderType)).subtracting(getResponders().map { "\(type(of: $0))" }))")
    }

    public mutating func append(_ ref: ResponderRefMaker<Responder>) {
        dispatchPrecondition(condition: .onQueue(.main))
        assert(ref.ref.responder != nil)

        responderRefs.append(ref.ref)
    }

    public func getResponders() -> [Responder] {
        return responderRefs.compactMap(\.responder)
    }

}

extension ResponderChain: Sequence {

    public struct Iterator: IteratorProtocol {
        private var iterator: Array<ResponderRef<Responder>>.Iterator

        fileprivate init(refs: [ResponderRef<Responder>]) {
            self.iterator = refs.makeIterator()
        }

        public mutating func next() -> Responder? {
            while let ref = iterator.next() {
                if let responder = ref.responder {
                    return responder
                }
            }
            return nil
        }
    }

    public var underestimatedCount: Int {
        responderRefs.count
    }

    public func makeIterator() -> Iterator {
        Iterator(refs: responderRefs)
    }

}

public enum ResponderRef<Responder> {

    case weak(getter: () -> Responder?, type: Responder.Type)
    case strong(Responder)

    var responder: Responder? {
        switch self {
        case .weak(getter: let getter, type: _): return getter()
        case .strong(let responder): return responder
        }
    }

    var responderType: String {
        switch self {
        case .weak(getter: _, type: let type): return "\(type)"
        case .strong(let responder): return "\(type(of: responder))"
        }
    }

}

public struct ResponderRefMaker<Responder> {

    internal let ref: ResponderRef<Responder>

    private init(_ ref: ResponderRef<Responder>) {
        self.ref = ref
    }

    public static func `weak`<Responder: AnyObject>(_ responder: Responder) -> ResponderRefMaker<Responder> {
        return .init(ResponderRef<Responder>.weak(getter: { [weak responder] in responder }, type: type(of: responder)))
    }

    public static func `weak`<Responder: AnyObject>(nullable responder: Responder?) -> ResponderRefMaker<Responder>? {
        guard let responder = responder else { return nil }
        return .init(ResponderRef<Responder>.weak(getter: { [weak responder] in responder }, type: type(of: responder)))
    }

    public static func `strong`<Responder: AnyObject>(_ responder: Responder) -> ResponderRefMaker<Responder> {
        return .init(ResponderRef<Responder>.strong(responder))
    }

    public static func `strong`<Responder: AnyObject>(nullable responder: Responder?) -> ResponderRefMaker<Responder>? {
        guard let responder = responder else { return nil }
        return .init(ResponderRef<Responder>.strong(responder))
    }

    public static func `struct`<Responder>(_ responder: Responder) -> ResponderRefMaker<Responder> {
        assert(Mirror(reflecting: responder).displayStyle == .struct, "\(type(of: responder)) is not a struct")
        return .init(ResponderRef<Responder>.strong(responder))
    }

    public static func `struct`<Responder>(nullable responder: Responder?) -> ResponderRefMaker<Responder>? {
        guard let responder = responder else { return nil }
        return .struct(responder)
    }

}
