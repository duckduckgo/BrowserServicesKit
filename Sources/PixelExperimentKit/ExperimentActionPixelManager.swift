//
//  ExperimentActionPixelManager.swift
//  DuckDuckGo
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

public protocol ExperimentActionPixelStore {
     func removeObject(forKey defaultName: String)
     func integer(forKey defaultName: String) -> Int
     func set(_ value: Int, forKey defaultName: String)
 }

public protocol ExperimentActionPixelManaging {
    func incrementAndCheck(forKey key: String, threshold: Int) -> Bool
}

public struct ExperimentActionPixelManager: ExperimentActionPixelManaging {
    let store: ExperimentActionPixelStore
    private let syncQueue = DispatchQueue(label: "com.pixelkit.experimentActionSyncQueue")

    public init(store: ExperimentActionPixelStore = UserDefaults.standard) {
        self.store = store
    }

    public func incrementAndCheck(forKey key: String, threshold: Int) -> Bool {
        syncQueue.sync {
            let currentCount = store.integer(forKey: key)
            let newCount = currentCount + 1
            store.set(newCount, forKey: key)

            if newCount >= threshold {
                store.removeObject(forKey: key)
                return true
            }
            return false
        }
    }
}

extension UserDefaults: ExperimentActionPixelStore {}
