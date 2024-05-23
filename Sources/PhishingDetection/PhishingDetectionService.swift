//
//  PhishingDetectionService.swift
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
import CryptoKit
import Common

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

public protocol PhishingDetectionServiceProtocol {
    func isMalicious(url: URL) async -> Bool
    func updateFilterSet() async
    func updateHashPrefixes() async
}

enum PhishingDetectionDataError: Error {
    case empty
}

public class PhishingDetectionService: PhishingDetectionServiceProtocol {
    var filterSet: Set<Filter> = []
    var hashPrefixes = Set<String>()
    var currentRevision = 0
    var apiClient: PhishingDetectionClientProtocol
    var dataStore: URL?
    

    public init(apiClient: PhishingDetectionClientProtocol? = nil) {
        self.apiClient = apiClient ?? PhishingDetectionAPIClient() as PhishingDetectionClientProtocol
        createDataStore()
    }
    
    public func updateFilterSet() async {
        let response = await apiClient.getFilterSet(revision: currentRevision)
        if response.replace {
            currentRevision = response.revision
            self.filterSet = Set(response.insert)
        } else {
            currentRevision = response.revision
            response.insert.forEach { self.filterSet.insert($0) }
            response.delete.forEach { self.filterSet.remove($0) }
        }
    }

    public func updateHashPrefixes() async {
        let response = await apiClient.getHashPrefixes(revision: currentRevision)
        if response.replace {
            currentRevision = response.revision
            self.hashPrefixes = Set(response.insert)
        } else {
            currentRevision = response.revision
            response.insert.forEach { self.hashPrefixes.insert($0) }
            response.delete.forEach { self.hashPrefixes.remove($0) }
        }
    }

    public func getMatches(hashPrefix: String) async -> Set<Match> {
        return Set(await apiClient.getMatches(hashPrefix: hashPrefix))
    }

    func inFilterSet(hash: String) -> Set<Filter> {
        return Set(filterSet.filter { $0.hashValue == hash })
    }
    
    func matchesUrl(hash: String, regexPattern: String, url: URL, hostnameHash: String) -> Bool {
        if hash == hostnameHash,
           let regex = try? NSRegularExpression(pattern: regexPattern, options: [])
        {
            let urlString = url.absoluteString
            let range = NSRange(location: 0, length: urlString.utf16.count)
            return regex.firstMatch(in: urlString, options: [], range: range) != nil
        }
        return false
    }

    public func isMalicious(url: URL) async -> Bool {
        guard let canonicalHost = url.canonicalHost() else { return false }
        let hostnameHash = SHA256.hash(data: Data(canonicalHost.utf8)).map { String(format: "%02hhx", $0) }.joined()
        let hashPrefix = String(hostnameHash.prefix(8))
        if hashPrefixes.contains(hashPrefix) {
            // Check local filterSet first
            let filterHit = inFilterSet(hash: hostnameHash)
            for filter in filterHit {
                if matchesUrl(hash: filter.hashValue, regexPattern: filter.regex, url: url, hostnameHash: hostnameHash) {
                    return true
                }
            }
            // If nothing found, hit the API to get matches
            let matches = await apiClient.getMatches(hashPrefix: hashPrefix)
            for match in matches {
                if matchesUrl(hash: match.hash, regexPattern: match.regex, url: url, hostnameHash: hostnameHash) {
                    return true
                }
            }
        }
        return false
    }

    func createDataStore() {
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
            if hashPrefixes.isEmpty && filterSet.isEmpty {
                throw PhishingDetectionDataError.empty
            }
            let hashPrefixesData = try encoder.encode(Array(hashPrefixes))
            let filterSetData = try encoder.encode(Array(filterSet))

            let hashPrefixesFileURL = dataStore!.appendingPathComponent("hashPrefixes.json")
            let filterSetFileURL = dataStore!.appendingPathComponent("filterSet.json")

            try hashPrefixesData.write(to: hashPrefixesFileURL)
            try filterSetData.write(to: filterSetFileURL)
        } catch {
            os_log(.debug, log: .phishingDetection, "\(self): 🔴 Error saving phishing protection data: \(error)")
        }
    }

    public func loadData() {
        let decoder = JSONDecoder()
        do {
            let hashPrefixesFileURL = dataStore!.appendingPathComponent("hashPrefixes.json")
            let filterSetFileURL = dataStore!.appendingPathComponent("filterSet.json")

            let hashPrefixesData = try Data(contentsOf: hashPrefixesFileURL)
            let filterSetData = try Data(contentsOf: filterSetFileURL)

            hashPrefixes = Set(try decoder.decode([String].self, from: hashPrefixesData))
            filterSet = Set(try decoder.decode([Filter].self, from: filterSetData))
            
            if hashPrefixes.isEmpty && filterSet.isEmpty {
                throw PhishingDetectionDataError.empty
            }
        } catch {
            os_log(.debug, log: .phishingDetection, "\(self): 🔴 Error loading phishing protection data: \(error)")
            Task {
                await self.updateFilterSet()
                await self.updateHashPrefixes()
                self.writeData()
            }
        }
    }
    
}