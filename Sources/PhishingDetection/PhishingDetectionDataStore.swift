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

public protocol PhishingDetectionDataSets {
    var filterSet: Set<Filter> { get }
    var hashPrefixes: Set<String> { get }
    var currentRevision: Int { get }
}

public protocol PhishingDetectionDataSaving {
    func saveFilterSet(set: Set<Filter>)
    func saveHashPrefixes(set: Set<String>)
    func saveRevision(_ revision: Int)
}

public protocol PhishingDetectionDataFileStoring {
    func writeData()
    func loadData() async
}

public class PhishingDetectionDataStore: PhishingDetectionDataSets, PhishingDetectionDataSaving, PhishingDetectionDataFileStoring {
    public var filterSet: Set<Filter> = []
    public var hashPrefixes = Set<String>()
    public var currentRevision = 0

    var dataProvider: PhishingDetectionDataProviding
    var fileStorageManager: FileStorageManager

    public init(dataProvider: PhishingDetectionDataProviding) {
        self.dataProvider = dataProvider

        let dataStoreDirectory: URL
        do {
            dataStoreDirectory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        } catch {
            os_log(.debug, log: .phishingDetection, "\(self): 🔴 Error accessing application support directory: \(error)")
            dataStoreDirectory = FileManager.default.temporaryDirectory
        }
        let dataStoreURL = dataStoreDirectory.appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true)
        self.fileStorageManager = FileStorageManager(dataStoreURL: dataStoreURL)
    }

    public func saveFilterSet(set: Set<Filter>) {
        self.filterSet = set
    }

    public func saveHashPrefixes(set: Set<String>) {
        self.hashPrefixes = set
    }

    public func saveRevision(_ revision: Int) {
        self.currentRevision = revision
    }

    public func writeData() {
        let encoder = JSONEncoder()
        do {
            let hashPrefixesData = try encoder.encode(Array(hashPrefixes))
            let filterSetData = try encoder.encode(Array(filterSet))
            let revisionData = try encoder.encode(self.currentRevision)

            fileStorageManager.write(data: hashPrefixesData, to: "hashPrefixes.json")
            fileStorageManager.write(data: filterSetData, to: "filterSet.json")
            fileStorageManager.write(data: revisionData, to: "revision.txt")
        } catch {
            os_log(.debug, log: .phishingDetection, "\(self): 🔴 Error saving phishing protection data: \(error)")
        }
    }

    public func loadData() async {
        let decoder = JSONDecoder()
        do {
            guard let hashPrefixesData = fileStorageManager.read(from: "hashPrefixes.json"),
                  let filterSetData = fileStorageManager.read(from: "filterSet.json"),
                  let revisionData = fileStorageManager.read(from: "revision.txt") else {
                throw PhishingDetectionDataError.empty
            }

            hashPrefixes = Set(try decoder.decode([String].self, from: hashPrefixesData))
            filterSet = Set(try decoder.decode([Filter].self, from: filterSetData))
            currentRevision = try decoder.decode(Int.self, from: revisionData)

            if (hashPrefixes.isEmpty && filterSet.isEmpty) || currentRevision == 0 {
                throw PhishingDetectionDataError.empty
            }
        } catch {
            os_log(.debug, log: .phishingDetection, "\(self): 🔴 Error loading phishing protection data: \(error). Reloading from embedded dataset.")
            self.currentRevision = dataProvider.embeddedRevision
            self.hashPrefixes = dataProvider.loadEmbeddedHashPrefixes()
            self.filterSet = dataProvider.loadEmbeddedFilterSet()
        }
    }
}

class FileStorageManager {
    let dataStoreURL: URL

    init(dataStoreURL: URL) {
        self.dataStoreURL = dataStoreURL
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: dataStoreURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            os_log(.error, log: .default, "Failed to create directory: %{public}@", error.localizedDescription)
        }
    }

    func write(data: Data, to filename: String) {
        let fileURL = dataStoreURL.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
        } catch {
            os_log(.error, log: .default, "Error writing to %{public}@: %{public}@", filename, error.localizedDescription)
        }
    }

    func read(from filename: String) -> Data? {
        let fileURL = dataStoreURL.appendingPathComponent(filename)
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            os_log(.error, log: .default, "Error reading from %{public}@: %{public}@", filename, error.localizedDescription)
            return nil
        }
    }
}
