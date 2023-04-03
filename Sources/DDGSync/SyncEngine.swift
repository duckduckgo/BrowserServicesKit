//
//  SyncEngine.swift
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

import Foundation

public protocol Syncable: Codable {
    var lastModified: Date? { get set }
    var deleted: String? { get set }
}

public struct SyncFeature: OptionSet {
    public static let bookmarks = SyncFeature(rawValue: 1 << 0)
    public static let emailProtection = SyncFeature(rawValue: 1 << 1)
    public static let settings = SyncFeature(rawValue: 1 << 2)
    public static let autofill = SyncFeature(rawValue: 1 << 3)

    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public protocol SyncScheduling {
    func notifyDataChanged()
    func notifyAppLifecycleEvent()
}

public protocol SyncDataProviding {
    var supportedModels: SyncFeature { get }
    var metadataProvider: SyncMetadataProviding { get }

    func changes(for feature: SyncFeature, since timestamp: String) -> [Syncable]
}

public protocol SyncMetadataProviding {
    func lastSyncTimestamp(for feature: SyncFeature) -> String?
    func setLastSyncTimestamp(_ timestamp: String, for model: SyncFeature)
}

public protocol SyncEngineProtocol {
    var scheduler: SyncScheduling { get }
    var dataProvider: SyncDataProviding { get }

    func sync() async throws -> SyncResultProviding
}

public protocol SyncResultProviding {
    func lastSyncTimestamp(for feature: SyncFeature) -> String?
    func changes(for feature: SyncFeature) -> [Syncable]
}

// MARK: - Implementation

struct SyncScheduler: SyncScheduling {
    func notifyDataChanged() {
    }

    func notifyAppLifecycleEvent() {
    }
}

struct SyncDataProvider: SyncDataProviding {
    var supportedModels: SyncFeature {
        [.bookmarks]
    }

    let metadataProvider: SyncMetadataProviding

    init(metadataProvider: SyncMetadataProviding) {
        self.metadataProvider = metadataProvider
    }

    func changes(for feature: SyncFeature, since timestamp: String) -> [Syncable] {
        []
    }
}

struct SyncMetadataProvider: SyncMetadataProviding {
    func lastSyncTimestamp(for feature: SyncFeature) -> String? {
        nil
    }

    func setLastSyncTimestamp(_ timestamp: String, for model: SyncFeature) {
    }
}

struct SyncResultProvider: SyncResultProviding {
    func lastSyncTimestamp(for feature: SyncFeature) -> String? {
        nil
    }

    func changes(for feature: SyncFeature) -> [Syncable] {
        []
    }
}

class SyncEngine: SyncEngineProtocol {

    init(scheduler: SyncScheduling, dataProvider: SyncDataProviding) {
        self.scheduler = scheduler
        self.dataProvider = dataProvider
    }
    let scheduler: SyncScheduling
    let dataProvider: SyncDataProviding

    func sync() async throws -> SyncResultProviding {
        return SyncResultProvider()
    }
}
