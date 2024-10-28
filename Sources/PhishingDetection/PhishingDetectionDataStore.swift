//
//  PhishingDetectionDataStore.swift
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

enum PhishingDetectionDataError: Error {
    case empty
}

public struct Filter: Codable, Hashable {
	public var hashValue: String
	public var regex: String

	enum CodingKeys: String, CodingKey {
		case hashValue = "hash"
		case regex
	}

	public init(hashValue: String, regex: String) {
		self.hashValue = hashValue
		self.regex = regex
	}
}

public struct Match: Codable, Hashable {
	var hostname: String
	var url: String
	var regex: String
	var hash: String

	public init(hostname: String, url: String, regex: String, hash: String) {
		self.hostname = hostname
		self.url = url
		self.regex = regex
		self.hash = hash
	}
}

public protocol PhishingDetectionDataSaving {
    var filterSet: Set<Filter> { get }
    var hashPrefixes: Set<String> { get }
    var currentRevision: Int { get }
    func saveFilterSet(set: Set<Filter>)
    func saveHashPrefixes(set: Set<String>)
    func saveRevision(_ revision: Int)
}

public class PhishingDetectionDataStore: PhishingDetectionDataSaving {
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

    private let dataProvider: PhishingDetectionDataProviding
    private let fileStorageManager: FileStorageManager
    private let encoder = JSONEncoder()
    private let revisionFilename = "revision.txt"
    private let hashPrefixFilename = "hashPrefixes.json"
    private let filterSetFilename = "filterSet.json"

    public init(dataProvider: PhishingDetectionDataProviding,
                fileStorageManager: FileStorageManager? = nil) {
        self.dataProvider = dataProvider
        if let injectedFileStorageManager = fileStorageManager {
            self.fileStorageManager = injectedFileStorageManager
        } else {
            self.fileStorageManager = PhishingFileStorageManager()
        }
    }

    private func writeHashPrefixes() {
        let encoder = JSONEncoder()
        do {
            let hashPrefixesData = try encoder.encode(Array(hashPrefixes))
            fileStorageManager.write(data: hashPrefixesData, to: hashPrefixFilename)
        } catch {
            Logger.phishingDetectionDataStore.error("Error saving hash prefixes data: \(error.localizedDescription)")
        }
    }

    private func writeFilterSet() {
        let encoder = JSONEncoder()
        do {
            let filterSetData = try encoder.encode(Array(filterSet))
            fileStorageManager.write(data: filterSetData, to: filterSetFilename)
        } catch {
            Logger.phishingDetectionDataStore.error("Error saving filter set data: \(error.localizedDescription)")
        }
    }

    private func writeRevision() {
        let encoder = JSONEncoder()
        do {
            let revisionData = try encoder.encode(currentRevision)
            fileStorageManager.write(data: revisionData, to: revisionFilename)
        } catch {
            Logger.phishingDetectionDataStore.error("Error saving revision data: \(error.localizedDescription)")
        }
    }

    private func loadHashPrefix() -> Set<String> {
        guard let data = fileStorageManager.read(from: hashPrefixFilename) else {
            return dataProvider.loadEmbeddedHashPrefixes()
        }
        let decoder = JSONDecoder()
        do {
            if loadRevisionFromDisk() < dataProvider.embeddedRevision {
                return dataProvider.loadEmbeddedHashPrefixes()
            }
            let onDiskHashPrefixes = Set(try decoder.decode(Set<String>.self, from: data))
            return onDiskHashPrefixes
        } catch {
            Logger.phishingDetectionDataStore.error("Error decoding \(self.hashPrefixFilename): \(error.localizedDescription)")
            return dataProvider.loadEmbeddedHashPrefixes()
        }
    }

    private func loadFilterSet() -> Set<Filter> {
        guard let data = fileStorageManager.read(from: filterSetFilename) else {
            return dataProvider.loadEmbeddedFilterSet()
        }
        let decoder = JSONDecoder()
        do {
            if loadRevisionFromDisk() < dataProvider.embeddedRevision {
                return dataProvider.loadEmbeddedFilterSet()
            }
            let onDiskFilterSet = Set(try decoder.decode(Set<Filter>.self, from: data))
            return onDiskFilterSet
        } catch {
            Logger.phishingDetectionDataStore.error("Error decoding \(self.filterSetFilename): \(error.localizedDescription)")
            return dataProvider.loadEmbeddedFilterSet()
        }
    }

    private func loadRevisionFromDisk() -> Int {
        guard let data = fileStorageManager.read(from: revisionFilename) else {
            return dataProvider.embeddedRevision
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(Int.self, from: data)
        } catch {
            Logger.phishingDetectionDataStore.error("Error decoding \(self.revisionFilename): \(error.localizedDescription)")
            return dataProvider.embeddedRevision
        }
    }

    private func loadRevision() -> Int {
        guard let data = fileStorageManager.read(from: revisionFilename) else {
            return dataProvider.embeddedRevision
        }
        let decoder = JSONDecoder()
        do {
            let loadedRevision = try decoder.decode(Int.self, from: data)
            if loadedRevision < dataProvider.embeddedRevision {
                return dataProvider.embeddedRevision
            }
            return loadedRevision
        } catch {
            Logger.phishingDetectionDataStore.error("Error decoding \(self.revisionFilename): \(error.localizedDescription)")
            return dataProvider.embeddedRevision
        }
    }
}

extension PhishingDetectionDataStore {
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

public protocol FileStorageManager {
    func write(data: Data, to filename: String)
    func read(from filename: String) -> Data?
}

final class PhishingFileStorageManager: FileStorageManager {
    private let dataStoreURL: URL

    init() {
        let dataStoreDirectory: URL
        do {
            dataStoreDirectory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        } catch {
            Logger.phishingDetectionDataStore.error("Error accessing application support directory: \(error.localizedDescription)")
            dataStoreDirectory = FileManager.default.temporaryDirectory
        }
        dataStoreURL = dataStoreDirectory.appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true)
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: dataStoreURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.phishingDetectionDataStore.error("Failed to create directory: \(error.localizedDescription)")
        }
    }

    func write(data: Data, to filename: String) {
        let fileURL = dataStoreURL.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
        } catch {
            Logger.phishingDetectionDataStore.error("Error writing to directory: \(error.localizedDescription)")
        }
    }

    func read(from filename: String) -> Data? {
        let fileURL = dataStoreURL.appendingPathComponent(filename)
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            Logger.phishingDetectionDataStore.error("Error accessing application support directory: \(error)")
            return nil
        }
    }
}
