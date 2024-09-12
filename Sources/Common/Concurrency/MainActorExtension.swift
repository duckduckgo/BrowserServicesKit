//
//  MainActorExtension.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

#if swift(<5.10)
private protocol MainActorPerformer {
    func perform<T>(_ operation: @MainActor () throws -> T) rethrows -> T
}
private struct OnMainActor: MainActorPerformer {
    private init() {}
    static func instance() -> MainActorPerformer { OnMainActor() }

    @MainActor(unsafe)
    func perform<T>(_ operation: @MainActor () throws -> T) rethrows -> T {
        try operation()
    }
}
public extension MainActor {
    static func assumeIsolated<T>(_ operation: @MainActor () throws -> T) rethrows -> T {
        if #available(macOS 14.0, iOS 17.0, *) {
            return try assumeIsolated(operation, file: #fileID, line: #line)
        }
        dispatchPrecondition(condition: .onQueue(.main))
        return try OnMainActor.instance().perform(operation)
    }
}
#else
    // Don‘t remove it till we build UI tests on Xcode 15.2
    #warning("This needs to be removed as it‘s no longer necessary.")
#endif
