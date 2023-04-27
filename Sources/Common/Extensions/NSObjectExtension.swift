//
//  NSObjectExtension.swift
//  DuckDuckGo
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

import Combine
import Foundation

extension NSObject {

    final public class DeinitObserver: NSObject {
        fileprivate var callback: (() -> Void)?

        public init(_ callback: (() -> Void)? = nil) {
            dispatchPrecondition(condition: .onQueue(.main))
            self.callback = callback
        }

        public func disarm() {
            dispatchPrecondition(condition: .onQueue(.main))
            callback = nil
        }

        deinit {
            callback?()
        }
    }

    /// Add an observer for the object deallocation event
    /// be sure not to reference the object inside the callback as it would create a retain cycle
    @discardableResult
    public func onDeinit(_ onDeinit: @escaping () -> Void) -> DeinitObserver {
        dispatchPrecondition(condition: .onQueue(.main))
        if let deinitObserver = self as? DeinitObserver {
            assert(deinitObserver.callback == nil, "disarm DeinitObserver first before re-setting its callback")
            deinitObserver.callback = onDeinit
            return deinitObserver
        }
        return self.deinitObservers.insert(DeinitObserver(onDeinit)).memberAfterInsert
    }

    private static let deinitObserversKey = UnsafeRawPointer(bitPattern: "deinitObserversKey".hashValue)!
    public var deinitObservers: Set<DeinitObserver> {
        get {
            dispatchPrecondition(condition: .onQueue(.main))
            return objc_getAssociatedObject(self, Self.deinitObserversKey) as? Set<DeinitObserver> ?? []
        }
        set {
            dispatchPrecondition(condition: .onQueue(.main))
            objc_setAssociatedObject(self, Self.deinitObserversKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

#if DEBUG
    /// DEBUG-only runtime check for an expected object deallocation
    /// will raise an assertionFailure if the object is not deallocated after the timeout
    public func assertObjectDeallocated(after timeout: TimeInterval = 0) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.assertObjectDeallocated(after: timeout)
            }
            return
        }
        let assertion = DispatchWorkItem { [unowned self] in
            assertionFailure("\(self) has not been deallocated")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: assertion)
        self.onDeinit {
            assertion.cancel()
        }
    }
#else
    @inlinable
    public func assertObjectDeallocated(after timeout: TimeInterval = 0) {}
#endif

}
