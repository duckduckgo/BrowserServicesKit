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

    private static let deinitTrackersKey = UnsafeRawPointer(bitPattern: "deinitTrackersKey".hashValue)!
    private var deinitTrackers: [AnyCancellable] {
        get {
            objc_getAssociatedObject(self, Self.deinitTrackersKey) as? [AnyCancellable] ?? []
        }
        set {
            objc_setAssociatedObject(self, Self.deinitTrackersKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    public func onDeinit(_ onDeinit: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.deinitTrackers.append(AnyCancellable(onDeinit))
    }

#if DEBUG
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
