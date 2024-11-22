//
//  MaliciousSiteDataManager.swift
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
import Common
import os

public protocol DataManaging {
    var filterSet: Set<Filter> { get }
    var hashPrefixes: Set<String> { get }
    var currentRevision: Int { get }
    func saveFilterSet(set: Set<Filter>)
    func saveHashPrefixes(set: Set<String>)
    func saveRevision(_ revision: Int)
}

public final class DataManager: DataManaging {
    private lazy var _filterSet: Set<Filter> = {
        loadFilterSet()
    }()

    private lazy var _hashPrefixes: Set<String> = {
        loadHashPrefix()
    }()

    private lazy var _currentRevision: Int = {
        loadRevision()
    }()

    public private(set) var filterSet: Set<Filter> {
        get { _filterSet }
        set { _filterSet = newValue }
    }
    public private(set) var hashPrefixes: Set<String> {
        get { _hashPrefixes }
        set { _hashPrefixes = newValue }
    }
    public private(set) var currentRevision: Int {
        get { _currentRevision }
        set { _currentRevision = newValue }
    }

    private let embeddedDataProvider: EmbeddedDataProviding
    private let fileStore: FileStoring
    private let encoder = JSONEncoder()
    private let revisionFilename = "revision.txt"
    private let hashPrefixFilename = "phishingHashPrefixes.json"
    private let filterSetFilename = "phishingFilterSet.json"

    public init(embeddedDataProvider: EmbeddedDataProviding, fileStore: FileStoring? = nil) {
        self.embeddedDataProvider = embeddedDataProvider
        self.fileStore = fileStore ?? FileStore()
    }

    private func writeHashPrefixes() {
        let encoder = JSONEncoder()
        do {
            let hashPrefixesData = try encoder.encode(Array(hashPrefixes))
            fileStore.write(data: hashPrefixesData, to: hashPrefixFilename)
        } catch {
            Logger.dataManager.error("Error saving hash prefixes data: \(error.localizedDescription)")
        }
    }

    private func writeFilterSet() {
        let encoder = JSONEncoder()
        do {
            let filterSetData = try encoder.encode(Array(filterSet))
            fileStore.write(data: filterSetData, to: filterSetFilename)
        } catch {
            Logger.dataManager.error("Error saving filter set data: \(error.localizedDescription)")
        }
    }

    private func writeRevision() {
        let encoder = JSONEncoder()
        do {
            let revisionData = try encoder.encode(currentRevision)
            fileStore.write(data: revisionData, to: revisionFilename)
        } catch {
            Logger.dataManager.error("Error saving revision data: \(error.localizedDescription)")
        }
    }

    private func loadHashPrefix() -> Set<String> {
        guard let data = fileStore.read(from: hashPrefixFilename) else {
            return embeddedDataProvider.loadEmbeddedHashPrefixes()
        }
        let decoder = JSONDecoder()
        do {
            if loadRevisionFromDisk() < embeddedDataProvider.embeddedRevision {
                return embeddedDataProvider.loadEmbeddedHashPrefixes()
            }
            let onDiskHashPrefixes = Set(try decoder.decode(Set<String>.self, from: data))
            return onDiskHashPrefixes
        } catch {
            Logger.dataManager.error("Error decoding \(self.hashPrefixFilename): \(error.localizedDescription)")
            return embeddedDataProvider.loadEmbeddedHashPrefixes()
        }
    }

    private func loadFilterSet() -> Set<Filter> {
        guard let data = fileStore.read(from: filterSetFilename) else {
            return embeddedDataProvider.loadEmbeddedFilterSet()
        }
        let decoder = JSONDecoder()
        do {
            if loadRevisionFromDisk() < embeddedDataProvider.embeddedRevision {
                return embeddedDataProvider.loadEmbeddedFilterSet()
            }
            let onDiskFilterSet = Set(try decoder.decode(Set<Filter>.self, from: data))
            return onDiskFilterSet
        } catch {
            Logger.dataManager.error("Error decoding \(self.filterSetFilename): \(error.localizedDescription)")
            return embeddedDataProvider.loadEmbeddedFilterSet()
        }
    }

    private func loadRevisionFromDisk() -> Int {
        guard let data = fileStore.read(from: revisionFilename) else {
            return embeddedDataProvider.embeddedRevision
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(Int.self, from: data)
        } catch {
            Logger.dataManager.error("Error decoding \(self.revisionFilename): \(error.localizedDescription)")
            return embeddedDataProvider.embeddedRevision
        }
    }

    private func loadRevision() -> Int {
        guard let data = fileStore.read(from: revisionFilename) else {
            return embeddedDataProvider.embeddedRevision
        }
        let decoder = JSONDecoder()
        do {
            let loadedRevision = try decoder.decode(Int.self, from: data)
            if loadedRevision < embeddedDataProvider.embeddedRevision {
                return embeddedDataProvider.embeddedRevision
            }
            return loadedRevision
        } catch {
            Logger.dataManager.error("Error decoding \(self.revisionFilename): \(error.localizedDescription)")
            return embeddedDataProvider.embeddedRevision
        }
    }
}

extension DataManager {
    public func saveFilterSet(set: Set<Filter>) {
        self.filterSet = set
        writeFilterSet()
    }

    public func saveHashPrefixes(set: Set<String>) {
        self.hashPrefixes = set
        writeHashPrefixes()
    }

    public func saveRevision(_ revision: Int) {
        self.currentRevision = revision
        writeRevision()
    }
}
