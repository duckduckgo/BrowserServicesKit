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

public struct Filter: Decodable, Encodable, Hashable {
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

public struct Match: Decodable, Encodable, Hashable {
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

public protocol PhishingDetectionDataStoring {
    var filterSet: Set<Filter> { get set }
    var hashPrefixes: Set<String> { get set }
    var currentRevision: Int { get set }
    func writeData()
    func loadData() async
}

public class PhishingDetectionDataStore: PhishingDetectionDataStoring {
    public var filterSet: Set<Filter> = []
    public var hashPrefixes = Set<String>()
    public var currentRevision = 0

    var dataProvider: PhishingDetectionDataProviding
    var dataStore: URL?
    var hashPrefixFilename: String = "hashPrefixes.json"
    var filterSetFilename: String = "filterSet.json"
    var revisionFilename: String = "revision.txt"

    public init(dataProvider: PhishingDetectionDataProviding) {
        self.dataProvider = dataProvider
        createFileDataStore()
    }

    func createFileDataStore() {
        do {
            let fileManager = FileManager.default
            let appSupportDirectory = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            dataStore = appSupportDirectory.appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true)
            try fileManager.createDirectory(at: dataStore!, withIntermediateDirectories: true, attributes: nil)
        } catch {
            os_log(.debug, log: .phishingDetection, "\(self): 🔴 Error creating phishing protection data directory: \(error)")
        }
    }

    public func writeData() {
        let encoder = JSONEncoder()
        do {
            let hashPrefixesData = try encoder.encode(Array(hashPrefixes))
            let filterSetData = try encoder.encode(Array(filterSet))
            let revision = try encoder.encode(self.currentRevision)

            let hashPrefixesFileURL = dataStore!.appendingPathComponent(hashPrefixFilename)
            let filterSetFileURL = dataStore!.appendingPathComponent(filterSetFilename)
            let revisionFileURL = dataStore!.appendingPathComponent(revisionFilename)

            try hashPrefixesData.write(to: hashPrefixesFileURL)
            try filterSetData.write(to: filterSetFileURL)
            try revision.write(to: revisionFileURL)
        } catch {
            os_log(.debug, log: .phishingDetection, "\(self): 🔴 Error saving phishing protection data: \(error)")
        }
    }

    public func loadData() async {
        let decoder = JSONDecoder()
        do {
            let hashPrefixesFileURL = dataStore!.appendingPathComponent("hashPrefixes.json")
            let filterSetFileURL = dataStore!.appendingPathComponent("filterSet.json")
            let revisionFileURL = dataStore!.appendingPathComponent("revision.txt")

            let hashPrefixesData = try Data(contentsOf: hashPrefixesFileURL)
            let filterSetData = try Data(contentsOf: filterSetFileURL)
            let revisionData = try Data(contentsOf: revisionFileURL)

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
